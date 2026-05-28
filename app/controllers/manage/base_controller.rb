class Manage::BaseController < ApplicationController
  before_action :set_mission
  before_action :authorize_mission_management

  private

  def set_mission
    slug = params[:mission_slug] || params[:slug]
    @mission = Mission.find_by!(slug: slug)
  end

  def authorize_mission_management
    authorize @mission, :manage?
  end
end
