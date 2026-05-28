class Projects::ShipsController < ApplicationController
  before_action :set_project
  before_action :setup_chrome,    only: [ :new, :info, :review_step, :compose, :create ]
  before_action :require_shippable, only: [ :review_step, :compose, :create ]

  # Step 0 — "what is a ship" refresher (video only). Entry point.
  def new
    authorize @project, :ship?
    @step = 0
  end

  # Step 1 — project info form. Available regardless of shippable? state,
  # since this is the screen where you fix unmet requirements.
  def info
    authorize @project, :ship?
    @step = 1
    @project_times = current_user.try_sync_hackatime_data!&.dig(:projects) || {}
  end

  # Step 2 — review instructions form. Requires the project to be shippable
  # (handled by the before_action).
  def review_step
    authorize @project, :ship?
    @step = 2
  end

  # Step 3 — ship composer. Same shippable gate as step 2.
  def compose
    authorize @project, :ship?
    @step = 3
    @last_ship = @project.last_ship_event
  end

  def create
    authorize @project, :ship?
    # Read non-destructively — a redirect back (e.g. missing ack) must not
    # clear steps 2 & 3 from the wizard.
    wizard = session[:ship_wizard] || {}
    review_instructions = (wizard["review_instructions"].presence || params[:review_instructions]).to_s.strip.presence
    mission_payout_path = wizard["mission_payout_path"].presence || params[:mission_payout_path]
    submission_guide_ack = wizard.fetch("mission_submission_guide_acknowledged", false) ||
                           params[:mission_submission_guide_acknowledged].to_s == "1"

    if mission_submission_guide_ack_required? && !submission_guide_ack
      redirect_to review_project_ships_path(@project),
                  alert: "Read and acknowledge the mission submission guide before shipping." and return
    end

    session.delete(:ship_wizard)

    unless @project.readme_is_raw_github_url?
      flash.now[:warning] = "Your README link doesn't appear to be a raw GitHub URL. We require raw README files (from raw.githubusercontent.com) for proper display and consistency. Please update your README URL."
    end

    reship = has_previous_approved_ships?
    probe_result = reship ? ProjectUrlProbeService.new(@project).call : nil

    @project.with_lock do
      @project.submit_for_review!
      ship_event = Post::ShipEvent.create!(
        body: params[:ship_update].to_s.strip,
        review_instructions: review_instructions
      )
      @post = @project.posts.create!(user: current_user, postable: ship_event)
      maybe_create_mission_submission(ship_event, mission_payout_path, submission_guide_ack)

      # First Ship: Always create ship certification for manual review    ----------- Ask @AVD if you want to change this! - May need to notify teams of any changes!
      # Reships: If links alive - approves project, create a 'reship' YSWS review, if links dead - Creates ship cert for manual review
      if !reship
        @project.ship_reviews.create!(status: :pending)
      elsif probe_result.ok?
        # Reship with passing URLs: move through review, auto-approve, create YSWS review.
        # approve only transitions from :under_review, so we must start_review first.
        @project.start_review!
        @project.approve!
        @post.postable.update!(certification_status: "approved")
        maybe_create_ysws_review(ship_event)
      else
        @project.ship_reviews.create!(
          status: :returned,
          feedback: "Automated URL check failed: #{probe_result.failures.join('; ')}. Fix and re-ship."
        )
      end
    end

    if !reship
      redirect_to project_path(@project), notice: "Congratulations! Your project has been submitted for review!"
    elsif probe_result.ok?
      redirect_to project_path(@project), notice: "Ship submitted! Your project is now out for voting."
    else
      redirect_to project_path(@project), notice: "Your project needs changes. We couldn't reach your demo or repo. Fix those and re-ship."
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: new_project_ships_path(@project), alert: e.record.errors.full_messages.to_sentence
  end

  private
    def set_project
      @project = Project.find(params[:project_id])
    end

    # Shared chrome state for every wizard step: hide the global sidebar and
    # apply the ship-page body class so the layout knows we're in the wizard.
    def setup_chrome
      @hide_sidebar = true
      @body_class = "ship-page"
    end

    # Steps 2 and 3 can only be reached once the project meets every shipping
    # requirement. If a user lands on those URLs early (typed-in URL, stale
    # bookmark, mid-flow regression after editing project info), bounce them
    # back to the info step where they can fix things.
    def require_shippable
      return if @project.shippable?
      redirect_to info_project_ships_path(@project)
    end

    def initial_ship?
      @project.posts.where(postable_type: "Post::ShipEvent").one?
    end

    def mission_submission_guide_ack_required?
      @project.current_mission&.submission_guide.present?
    end

    def maybe_create_mission_submission(ship_event, payout_path_param, submission_guide_acknowledged = false)
      attachment = @project.current_mission_attachment
      return unless attachment

      mission = attachment.mission
      payout_path = resolve_payout_path(mission, payout_path_param)
      ack_time = (submission_guide_acknowledged && mission.submission_guide.present?) ? Time.current : nil

      # Don't pass status — AASM defaults it and rejects direct assignment.
      Mission::Submission.create!(
        ship_event: ship_event,
        mission: mission,
        payout_path: payout_path,
        submission_guide_acknowledged_at: ack_time
      )
    end

    def resolve_payout_path(mission, payout_path_param)
      return "voting" unless mission.has_prizes?
      return "voting" if user_redeemed_prize_for?(mission)
      payout_path_param.to_s == "voting" ? "voting" : "static_prize"
    end

    def user_redeemed_prize_for?(mission)
      Mission::Submission
        .where(mission_id: mission.id)
        .joins(ship_event: { post: :user })
        .where(users: { id: current_user.id })
        .where.not(shop_order_id: nil)
        .exists?
    end

    def maybe_create_ysws_review(ship_event) # Only create review if this is NOT the first ship (i.e., there are previous approved ships)
      return unless has_previous_approved_ships?(excluding_ship_event: ship_event) # excl: as ship event created before
      Certification::YswsReviewCreator.new(
        ship_event: ship_event,
        user: current_user,
        project: @project
      ).call
    end

    def has_previous_approved_ships?(excluding_ship_event: nil) # this could be scoped. note that post:ship_event is source of truth for ship events, as ship certifications aren't made for each ship event
      if excluding_ship_event
        @project.posts
          .joins("INNER JOIN post_ship_events ON posts.postable_id = post_ship_events.id AND posts.postable_type = 'Post::ShipEvent'")
          .where(post_ship_events: { certification_status: "approved" })
          .where.not(post_ship_events: { id: excluding_ship_event.id })
          .exists?
      else
        @project.posts
          .joins("INNER JOIN post_ship_events ON posts.postable_id = post_ship_events.id AND posts.postable_type = 'Post::ShipEvent'")
          .where(post_ship_events: { certification_status: "approved" })
          .exists?
      end
    end
end
