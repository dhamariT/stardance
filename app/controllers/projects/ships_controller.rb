class Projects::ShipsController < ApplicationController
  before_action :set_project

  def new
    authorize @project, :ship?
    @hide_sidebar = true
    @body_class = "ship-page"
    @step = params[:step]&.to_i&.clamp(1, 3) || 1
    @step = 1 if @step > 1 && !@project.shippable?
    load_step_data
  end

  def create
    # authorize @project, :ship?
    @hide_sidebar = true
    @body_class = "ship-page"

    wizard = session.delete(:ship_wizard) || {}
    review_instructions = (wizard["review_instructions"].presence || params[:review_instructions]).to_s.strip.presence
    mission_payout_path = wizard["mission_payout_path"].presence || params[:mission_payout_path]

    unless @project.readme_is_raw_github_url?
      flash.now[:warning] = "Your README link doesn't appear to be a raw GitHub URL. We require raw README files (from raw.githubusercontent.com) for proper display and consistency. Please update your README URL."
    end

    reship = had_prior_ship_event?
    probe_result = reship ? ProjectUrlProbeService.new(@project).call : nil

    @project.with_lock do
      @project.submit_for_review!
      ship_event = Post::ShipEvent.create!(
        body: params[:ship_update].to_s.strip,
        review_instructions: review_instructions
      )
      @post = @project.posts.create!(user: current_user, postable: ship_event)
      maybe_create_mission_submission(ship_event, mission_payout_path)
    end

    if !reship
      redirect_to project_path(@project), notice: "Congratulations! Your project has been submitted for review!"
    elsif probe_result.ok?
      @post.postable.update!(certification_status: "approved")
      redirect_to project_path(@project), notice: "Ship submitted! Your project is now out for voting."
    else
      @project.ship_reviews.pending.first&.update!(
        status: :returned,
        feedback: "Automated URL check failed: #{probe_result.failures.join('; ')}. Fix and re-ship."
      )
      redirect_to project_path(@project), notice: "Your project needs changes. We couldn't reach your demo or repo. Fix those and re-ship."
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: new_project_ships_path(@project), alert: e.record.errors.full_messages.to_sentence
  end

  private
    def set_project
      @project = Project.find(params[:project_id])
    end

    def load_step_data
      if @step == 1
        @project_times = current_user.try_sync_hackatime_data!&.dig(:projects) || {}
      elsif @step == 3
        @last_ship = @project.last_ship_event
      end
    end

    def initial_ship?
      @project.posts.where(postable_type: "Post::ShipEvent").one?
    end

    def had_prior_ship_event?
      @project.posts.where(postable_type: "Post::ShipEvent").exists?
    end

    def maybe_create_mission_submission(ship_event, payout_path_param)
      return unless Flipper.enabled?(:missions, current_user)
      attachment = @project.current_mission_attachment
      return unless attachment

      mission = attachment.mission
      payout_path = resolve_payout_path(mission, payout_path_param)

      Mission::Submission.create!(
        ship_event: ship_event,
        mission: mission,
        payout_path: payout_path,
        status: "awaiting_certification"
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
end
