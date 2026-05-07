class My::SettingsController < ApplicationController
  before_action :require_login

  def update
    current_user.update(hcb_email: params[:hcb_email].presence)
    current_user.preference.update!(
      send_votes_to_slack: params[:send_votes_to_slack] == "1",
      leaderboard_optin: params[:leaderboard_optin] == "1",
      stardust_balance_notifications: params[:stardust_balance_notifications] == "1",
      send_notifications_for_followed_projects: params[:send_notifications_for_followed_projects] == "1",
      send_notifications_for_new_followers: params[:send_notifications_for_new_followers] == "1",
      send_notifications_for_new_comments: params[:send_notifications_for_new_comments] == "1",
      search_engine_indexing_off: params[:search_engine_indexing_off] == "1"
    )
    redirect_back fallback_location: root_path, notice: "Settings saved"
  end

  private
    def require_login
      redirect_to root_path, alert: "Please log in first" and return unless current_user
    end
end
