require "test_helper"

class User::TutorialSteps::CompletionsControllerTest < ActionDispatch::IntegrationTest
  test "creates tutorial step completion" do
    user = users(:one)
    user.update_columns(tutorial_steps_completed: [])
    sign_in user

    post user_tutorial_step_completion_path(:setup_hackatime), as: :json

    assert_response :success
    assert user.reload.tutorial_step_completed?(:setup_hackatime)
  end
end
