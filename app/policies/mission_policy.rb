class MissionPolicy < ApplicationPolicy
  def index? = true

  # Show page renders for all non-soft-deleted missions, even if windowed
  # outside the start/end range or disabled — historical and "coming soon"
  # links shouldn't 404. Soft-deleted missions remain hidden because the
  # default scope excludes them; this policy never sees them.
  def show? = true
  def guide? = true

  def manage?
    return false unless user.present?
    user.admin? || record.memberships.exists?(user_id: user.id, role: :owner)
  end

  def destroy? = user&.admin?
end
