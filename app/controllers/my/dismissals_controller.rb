class My::DismissalsController < ApplicationController
  before_action :require_login

  def create
    if params[:thing_name].present?
      current_user.dismiss_thing!(params[:thing_name])
      head :ok
    else
      head :bad_request
    end
  rescue StandardError => e
    Rails.logger.error("Error dismissing thing: #{e.message}")
    head :internal_server_error
  end

  private
    def require_login
      redirect_to root_path, alert: "Please log in first" and return unless current_user
    end
end
