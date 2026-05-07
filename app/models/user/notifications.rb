module User::Notifications
  extend ActiveSupport::Concern

  def dm_user(message)
    SendSlackDmJob.perform_later(slack_id, message)
  end
end
