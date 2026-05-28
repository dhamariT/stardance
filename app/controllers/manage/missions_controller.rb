class Manage::MissionsController < Manage::BaseController
  MAX_PREVIEW_BYTES = 100_000
  MAX_PASTE_BYTES   = 200_000

  before_action :set_body_class

  def show
    redirect_to edit_manage_mission_path(@mission.slug)
  end

  def edit
    load_edit_locals
  end

  def update
    if @mission.update(mission_params)
      redirect_to edit_manage_mission_path(@mission.slug), notice: "Mission updated."
    else
      load_edit_locals
      render :edit, status: :unprocessable_entity
    end
  end

  # Paste-a-full-guide endpoint used by the modal in the Guide section.
  # Replaces the markdown for a named language. Updates an existing variant
  # in place, or creates a new one if the name is brand-new. The variant's
  # after_save callback rebuilds its steps to match.
  def paste_guide
    language_label = params[:language].to_s.strip
    body = params[:body].to_s

    if language_label.blank?
      redirect_to edit_manage_mission_path(@mission.slug),
                  alert: "Pick a language name first." and return
    end

    if body.bytesize > MAX_PASTE_BYTES
      redirect_to edit_manage_mission_path(@mission.slug, language: language_label),
                  alert: "Guide is too large (#{(body.bytesize / 1024.0).round}KB). Max is #{MAX_PASTE_BYTES / 1024}KB." and return
    end

    if Mission.guide_paste_preamble(body).present?
      redirect_to edit_manage_mission_path(@mission.slug, language: language_label),
                  alert: "Move any intro text inside the first step — the guide must start with an `## H2 heading`." and return
    end

    # Match case-insensitively so re-pasting `python` finds the existing
    # `Python` variant instead of tripping the case-insensitive uniqueness
    # validation on save.
    variant = @mission.guide_variants
                       .where("LOWER(language) = ?", language_label.downcase)
                       .first ||
              @mission.guide_variants.new(
                language: language_label,
                position: (@mission.guide_variants.maximum(:position).to_i + 1)
              )
    variant.body = body
    variant.save!

    redirect_to edit_manage_mission_path(@mission.slug, language: variant.language),
                notice: "Guide replaced for #{variant.language}."
  end

  # Live preview endpoint for submission_guide. Author-only — the standing
  # authorize in Manage::BaseController gates this to mission owners and
  # admins. Capped at 100 KB so a runaway paste can't burn the renderer.
  #
  # Renders the same intro + numbered-criteria-cards + outro partial the
  # public mission page uses, so authors see the partitioned layout — not
  # a flat <ul> of bullets.
  def preview_guide
    return head :payload_too_large if params[:markdown].to_s.bytesize > MAX_PREVIEW_BYTES
    preview_mission = Mission.new(submission_guide: params[:markdown].to_s)
    render partial: "missions/submission_requirements", locals: { mission: preview_mission }
  end

  private

  def set_body_class
    @body_class = "app-layout-page"
  end

  # Shared ivars for both successful and unprocessable_entity renders of edit.
  # Resolves the requested language tab and loads the per-section locals the
  # partials need.
  def load_edit_locals
    @current_language    = @mission.resolve_storage_language(params[:language].presence)
    @available_languages = @mission.available_languages

    # body_for is .detect-based, so preloading :bodies turns the per-step
    # body lookup into a single SELECT + in-memory pick. For an edit modal
    # rendering N steps, that's 1 query instead of N. The "wasted load" of
    # other-language bodies is small (typically 1-4 rows per step) and well
    # worth dropping N round-trips.
    @steps       = @mission.steps.where(deleted_at: nil).ordered.includes(:bodies)
    @prizes      = @mission.prizes.ordered.includes(:shop_item)
    @memberships = @mission.memberships.includes(:user).order(:role, :id)
    @unlocks     = @mission.shop_unlocks.includes(:shop_item)
  end

  def mission_params
    params.require(:mission).permit(
      :name, :description, :difficulty, :submission_guide,
      :enabled, :start_at, :end_at, :featured_at,
      :achievement_name, :achievement_description, :icon, :banner,
      :estimated_completion_minutes,
      :default_project_title, :default_project_description
    )
  end
end
