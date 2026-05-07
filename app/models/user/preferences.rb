module User::Preferences
  extend ActiveSupport::Concern

  included do
    after_create :create_default_preference!
  end

  private
    def create_default_preference!
      create_preference! unless preference
    end
end
