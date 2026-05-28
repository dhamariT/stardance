class Projects::MissionSectionCompletionsController < ApplicationController
  before_action :set_project

  # Single toggle endpoint. POST { mission_step_id, completed } and we
  # upsert / destroy the (project, mission_step) row. Completion is keyed on
  # mission_step_id so it's shared across every language the step has a body
  # in. Returns 200 on success.
  def create
    authorize @project, :update?

    desired = ActiveModel::Type::Boolean.new.cast(params[:completed])

    # Look up the step unscoped on un-tick so users can always clear their
    # own old completions even if the step (or the mission attachment) was
    # removed underneath them. The create branch keeps the active-step +
    # active-attachment guard so we never INSERT completions against
    # detached / soft-deleted state.
    step_scope = desired ? Mission::Step.where(deleted_at: nil) : Mission::Step.unscoped
    step = step_scope.find_by(id: params[:mission_step_id])
    return head :unprocessable_entity if step.nil?

    if desired
      # Only allow new completions against missions actively attached to
      # this project. Without this, anyone with project update? could
      # write rows for arbitrary missions that would inflate progress on
      # any future attach.
      unless @project.mission_attachments.where(mission_id: step.mission_id, detached_at: nil).exists?
        return head :unprocessable_entity
      end

      # find_or_create_by! fires AR callbacks (PaperTrail records the
      # version); the rescue handles the concurrent-POST race against the
      # (project, mission_step) unique index — the loser is a no-op.
      begin
        @project.mission_section_completions.find_or_create_by!(mission_step_id: step.id) do |c|
          c.mission_id    = step.mission_id
          c.completed_at  = Time.current
        end
      rescue ActiveRecord::RecordNotUnique
        # already exists, treat as success
      end
    else
      @project.mission_section_completions.where(mission_step_id: step.id).destroy_all
    end

    respond_to do |format|
      format.json { render json: { completed: desired } }
      format.any  { head :ok }
    end
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end
end
