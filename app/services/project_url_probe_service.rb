# frozen_string_literal: true

class ProjectUrlProbeService
  TIMEOUT = 5
  USER_AGENT = "Stardance-Ship-Probe/1.0"

  Result = Data.define(:ok, :failures) do
    def ok? = ok
  end

  def initialize(project)
    @project = project
  end

  def call
    failures = []
    failures << "demo URL didn't return success (#{@project.demo_url})" unless probe(@project.demo_url)
    failures << "repo URL didn't return success (#{@project.repo_url})" unless probe(@project.repo_url)
    Result.new(ok: failures.empty?, failures: failures)
  end

  private

  def probe(url)
    return false if url.blank?
    response = Faraday.new(url: url, headers: { "User-Agent" => USER_AGENT }) do |conn|
      conn.options.timeout = TIMEOUT
      conn.options.open_timeout = TIMEOUT
    end.get
    response.status.between?(200, 399)
  rescue StandardError
    false
  end
end
