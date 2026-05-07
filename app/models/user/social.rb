module User::Social
  extend ActiveSupport::Concern

  def follows?(other_user)
    return false if other_user.blank?

    follows_as_follower.exists?(followed_id: other_user.id)
  end
end
