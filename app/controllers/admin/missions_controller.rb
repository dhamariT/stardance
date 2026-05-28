module Admin
  class MissionsController < Admin::ApplicationController
    # Use the standard Stardance app layout for missions admin so the page
    # matches the rest of the site (sidebar, dark surface, brand chrome).
    # Other admin sections still inherit the tan kitchen layout via
    # Admin::ApplicationController.
    layout "application"

    before_action :set_body_class
    before_action :set_mission, only: [ :show, :edit, :update, :destroy, :restore ]

    def index
      authorize Mission

      # Default scope excludes soft-deleted; only the "deleted" filter opts in.
      scope = case params[:filter]
      when "active"
                # Enabled, started, not yet ended, not deleted.
                Mission.where(enabled: true)
                       .where("start_at IS NULL OR start_at <= ?", Time.current)
                       .where("end_at IS NULL OR end_at > ?", Time.current)
      when "disabled"
                Mission.where(enabled: false)
      when "deleted"
                Mission.with_deleted.where.not(deleted_at: nil)
      else
                Mission.all
      end
      @missions = scope.order(created_at: :desc).limit(200)
      @current_filter = params[:filter]
      @submission_counts = Mission::Submission.where(mission_id: @missions.map(&:id)).group(:mission_id).count
    end

    def new
      @mission = Mission.new
      authorize @mission
    end

    # New missions are created as disabled drafts with only the bare minimum
    # set (slug/name/description). Everything else — guide, prizes, reviewers,
    # default project copy, schedule, achievement, icon, banner — is filled
    # in on the manage page, which admins can always access. Redirecting
    # straight there cuts the create flow down to "claim a slug, then edit
    # like any other mission."
    def create
      @mission = Mission.new(mission_params.merge(enabled: false))
      authorize @mission

      if @mission.save
        redirect_to edit_manage_mission_path(@mission.slug),
                    notice: "Draft mission created — configure it below, then flip Enabled when it's ready."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def show
      authorize @mission
      @submissions = @mission.submissions.order(created_at: :desc).limit(50)

      mission_versions = PaperTrail::Version.where(item_type: "Mission", item_id: @mission.id.to_s)
      child_versions = child_audit_versions
      @versions = mission_versions.or(child_versions).order(created_at: :desc).limit(50)

      # Resolve whodunnit ids to a {id => User} map so the audit log shows
      # display names instead of bare numeric ids.
      whodunnit_ids = @versions.pluck(:whodunnit).compact.uniq
      @whodunnit_users = User.where(id: whodunnit_ids).index_by { |u| u.id.to_s }
    end

    def edit
      authorize @mission

      # Admin edit is intentionally minimal: slug, owner assignment, and
      # delete/restore. All mission content (title, description, guide,
      # prizes, reviewers, shop unlocks, default project copy, etc.) is
      # edited via the manage surface, which admins can access via Pundit's
      # `manage?` policy.
      @owners = @mission.memberships
                        .where(role: Mission::Membership.roles[:owner])
                        .includes(:user)
                        .order(:created_at)
    end

    def update
      authorize @mission

      if @mission.update(update_params)
        redirect_to admin_mission_path(@mission.slug), notice: "Mission slug updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @mission
      @mission.update!(deleted_at: Time.current, enabled: false)
      redirect_to admin_missions_path, notice: "Mission soft-deleted."
    end

    def restore
      authorize @mission, :restore?
      @mission.update!(deleted_at: nil)
      redirect_to admin_mission_path(@mission.slug), notice: "Mission restored."
    end

    private

    def set_body_class
      @body_class = "app-layout-page"
    end

    def set_mission
      @mission = Mission.with_deleted.find_by!(slug: params[:slug])
    end

    # PaperTrail's versions.item_id is a varchar. Keep each child id list
    # paired with its item_type so overlapping ids from another mission's
    # child table cannot leak into this audit feed.
    def child_audit_versions
      scopes = {
        "Mission::GuideVariant" => @mission.guide_variants.pluck(:id),
        "Mission::Step" => @mission.steps.with_deleted.pluck(:id),
        "Mission::Prize" => @mission.prizes.with_deleted.pluck(:id),
        "Mission::Membership" => @mission.memberships.pluck(:id),
        "Mission::ShopUnlock" => @mission.shop_unlocks.pluck(:id)
      }.filter_map do |item_type, ids|
        next if ids.empty?
        PaperTrail::Version.where(item_type: item_type, item_id: ids.map(&:to_s))
      end

      scopes.reduce(PaperTrail::Version.none) { |query, scope| query.or(scope) }
    end

    # Create permits only the three required fields — everything else is
    # configured on the manage page after the draft exists. Update permits
    # only the slug (admin's one prerogative the manage page doesn't offer).
    def mission_params
      params.require(:mission).permit(:slug, :name, :description)
    end

    def update_params
      params.require(:mission).permit(:slug)
    end
  end
end
