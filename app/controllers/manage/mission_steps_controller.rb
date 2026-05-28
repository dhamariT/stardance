class Manage::MissionStepsController < Manage::BaseController
  before_action :resolve_language
  before_action :set_step, only: [ :update, :destroy ]

  def create
    if @language.blank?
      redirect_to edit_manage_mission_path(@mission.slug),
                  alert: "Pick a language tab first (or paste a full guide to start one)." and return
    end

    if step_params[:body].to_s.strip.blank?
      redirect_to edit_manage_mission_path(@mission.slug, language: @language),
                  alert: "Step body can't be blank — write something for the #{@language} guide." and return
    end

    step = @mission.steps.new(
      title: step_params[:title],
      position: next_position
    )
    Mission::Step.transaction do
      step.save!
      step.upsert_body_for!(@language, step_params[:body])
    end
    @mission.regenerate_text_for_language!(@language)
    redirect_to edit_manage_mission_path(@mission.slug, language: @language),
                notice: "Step added."
  end

  def update
    if step_params[:direction].present?
      reorder!(step_params[:direction])
    else
      # Title is shared across languages; body is per-language. Update both
      # in one go.
      Mission::Step.transaction do
        @step.update!(title: step_params[:title]) if step_params[:title].present? && step_params[:title] != @step.title
        @step.upsert_body_for!(@language, step_params[:body]) if step_params.key?(:body)
      end
    end
    @mission.regenerate_text_for_language!(@language)
    redirect_to edit_manage_mission_path(@mission.slug, language: @language),
                notice: "Step updated."
  end

  def destroy
    # Deleting a step soft-deletes the shared row — affects every language
    # at once (which is the point of the shared-step refactor).
    @step.update!(deleted_at: Time.current)
    @mission.guide_variants.find_each do |v|
      @mission.regenerate_text_for_language!(v.language)
    end
    redirect_to edit_manage_mission_path(@mission.slug, language: @language),
                notice: "Step removed."
  end

  # Bulk reorder driven by the drag-handle Stimulus controller. Accepts a
  # JSON `order` array of step ids in their new order. Idempotent — sets
  # `position` on each step to match its index in the array.
  def reorder
    ids = Array(params[:order]).map(&:to_i)
    return head :unprocessable_entity if ids.empty?

    steps_by_id = @mission.steps.where(deleted_at: nil, id: ids).index_by(&:id)

    Mission::Step.transaction do
      ids.each_with_index do |id, idx|
        step = steps_by_id[id]
        next unless step
        # .update! (not update_all) so PaperTrail records a version per
        # position change — admin audit log shows who reshuffled steps.
        step.update!(position: idx + 1) if step.position != idx + 1
      end
    end

    # Reordering changes the H2 order in every language's variant body.
    @mission.guide_variants.find_each do |v|
      @mission.regenerate_text_for_language!(v.language)
    end

    head :ok
  end

  private

  # Resolve the URL `?language=...` to a canonical language label. Unknown
  # labels are passed through verbatim so brand-new tabs work — the variant
  # gets created the moment a step (or paste) lands.
  def resolve_language
    @language = @mission.resolve_storage_language(params[:language].presence)
  end

  def set_step
    @step = @mission.steps.find(params[:id])
  end

  def step_params
    params.require(:mission_step).permit(:title, :body, :direction)
  end

  def next_position
    (@mission.steps.maximum(:position) || 0) + 1
  end

  # Swap positions with the adjacent step in the requested direction.
  def reorder!(direction)
    siblings = @mission.steps.ordered.to_a
    idx = siblings.index { |s| s.id == @step.id }
    return unless idx

    target_idx = direction == "up" ? idx - 1 : idx + 1
    return if target_idx < 0 || target_idx >= siblings.length

    other = siblings[target_idx]
    Mission::Step.transaction do
      mine, theirs = @step.position, other.position
      @step.update!(position: theirs)
      other.update!(position: mine)
    end
  end
end
