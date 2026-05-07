require "test_helper"

class MyResourcesTest < ActionDispatch::IntegrationTest
  test "update_settings stores preference separately from user account fields" do
    user = users(:one)
    sign_in user

    patch my_settings_path, params: {
      hcb_email: "grants@example.test",
      send_votes_to_slack: "1",
      leaderboard_optin: "1",
      stardust_balance_notifications: "0",
      send_notifications_for_followed_projects: "1",
      send_notifications_for_new_followers: "1",
      search_engine_indexing_off: "1"
    }

    assert_redirected_to root_path
    assert_equal "grants@example.test", user.reload.hcb_email

    preference = user.preference.reload
    assert preference.send_votes_to_slack
    assert preference.leaderboard_optin
    assert_not preference.stardust_balance_notifications
    assert preference.send_notifications_for_followed_projects
    assert preference.send_notifications_for_new_followers
    assert_not preference.send_notifications_for_new_comments
    assert preference.search_engine_indexing_off
  end

  test "dismissal resource records dismissed thing" do
    user = users(:one)
    user.update_columns(things_dismissed: [])
    sign_in user

    post my_dismissals_path, params: { thing_name: "willsbuilds_banner" }

    assert_response :success
    assert user.reload.has_dismissed?("willsbuilds_banner")
  end
end
