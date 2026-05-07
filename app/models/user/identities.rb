module User::Identities
  extend ActiveSupport::Concern

  class_methods do
    # Add more providers only after adding them to PROVIDERS in user/identity.rb.
    def find_by_hackatime(uid) = find_by_provider("hackatime", uid)
    def find_by_idv(uid)       = find_by_provider("idv", uid)

    private
      def find_by_provider(provider, uid)
        joins(:identities).find_by(user_identities: { provider:, uid: })
      end
  end

  def hackatime_identity
    if identities.loaded?
      identities.find { |identity| identity.provider == "hackatime" }
    else
      identities.find_by(provider: "hackatime")
    end
  end

  def hack_club_identity
    if identities.loaded?
      identities.find { |identity| identity.provider == "hack_club" }
    else
      identities.find_by(provider: "hack_club")
    end
  end

  def has_hackatime?
    if identities.loaded?
      identities.any? { |identity| identity.provider == "hackatime" }
    else
      identities.exists?(provider: "hackatime")
    end
  end

  def has_identity_linked? = !verification_needs_submission?

  def setup_complete?
    has_hackatime? && has_identity_linked?
  end
end
