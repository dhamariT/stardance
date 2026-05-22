module Reviewer
  class ApplicationController < ::ApplicationController
    before_action :require_review_role

    private

    def require_review_role
      raise Pundit::NotAuthorizedError unless current_user&.can_review?
    end
  end
end
