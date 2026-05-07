class User::TutorialSteps::CompletionsController < ApplicationController
  before_action :require_login

  def create
    current_user.complete_tutorial_step!(params[:tutorial_step_id].to_sym)

    respond_to do |format|
      format.turbo_stream do
        @tutorial_steps = User::TutorialStep.all
        @completed_steps = current_user.tutorial_steps
        render turbo_stream: turbo_stream.replace(
          "tutorial-steps-container",
          HomeTutorialStepsComponent.new(
            tutorial_steps: @tutorial_steps,
            completed_steps: @completed_steps,
            current_user: current_user
          )
        )
      end
      format.json { head :ok }
      format.html { head :ok }
    end
  end

  private
    def require_login
      redirect_to root_path, alert: "Please log in first" and return unless current_user
    end
end
