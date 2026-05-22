# frozen_string_literal: true

module Posts
  class ComposerComponent < ViewComponent::Base
    delegate :inline_svg_tag, to: :helpers

    attr_reader :post, :current_user, :projects, :selected_project, :test_time_granted

    def initialize(post:, current_user:, projects:, selected_project:, test_time_granted: false)
      @post = post
      @current_user = current_user
      @projects = projects
      @selected_project = selected_project
      @test_time_granted = test_time_granted
    end

    def enabled?
      selected_project.present? && !setup_pending?
    end

    # Guest user who has already started the first-project setup flow but
    # hasn't finished linking HCA. Their draft project exists but should be
    # gated behind link completion — surface a "finish setup" prompt instead
    # of the regular composer or empty-state banner.
    def setup_pending?
      current_user&.has_pending_setup_project?
    end

    def hackatime_linked?
      test_time_granted || selected_project&.hackatime_keys&.present?
    end

    def preview_time_url
      helpers.preview_time_project_devlogs_path(selected_project)
    end
  end
end
