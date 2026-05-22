class Projects::Ships::ReviewsController < ApplicationController
  before_action :set_project

  def create
    authorize @project, :ship?

    session[:ship_wizard] = {
      "review_instructions" => params[:review_instructions].to_s.strip.presence,
      "mission_payout_path" => params[:mission_payout_path].to_s.strip.presence
    }

    redirect_to compose_project_ships_path(@project)
  end

  private
    def set_project
      @project = Project.find(params[:project_id])
    end
end
