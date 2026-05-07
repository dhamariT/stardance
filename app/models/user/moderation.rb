module User::Moderation
  extend ActiveSupport::Concern

  def ban!(reason: nil)
    update!(banned: true, banned_at: Time.current, banned_reason: reason)
    reject_pending_orders!(reason: reason || "User banned")
    soft_delete_projects!
  end

  def lock_voting_and_mark_votes_suspicious!(notify: false)
    return if voting_locked?

    transaction do
      update!(voting_locked: true)
      votes.update_all(suspicious: true)
    end

    if notify
      dm_user("Your voting has been locked due to suspicious activity. Please contact @Fraud Squad if you believe this is a mistake.")
    end
  end

  def soft_delete_projects!
    projects.find_each do |project|
      project.soft_delete!(force: true)
    end
  end

  def unban!
    update!(banned: false, banned_at: nil, banned_reason: nil)
  end
end
