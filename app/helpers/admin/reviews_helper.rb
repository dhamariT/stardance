module Admin::ReviewsHelper
  # Parse repo_url to extract platform and username information
  # Returns a hash with :platform, :platform_name, :username, and :icon
  # Example: { platform: "github", platform_name: "GitHub", username: "hackclub", icon: "github" }
  def parse_repo_info(repo_url)
    return nil if repo_url.blank?

    begin
      uri = URI.parse(repo_url)
    rescue URI::InvalidURIError
      return nil
    end

    return nil unless uri.host

    host = uri.host.downcase
    path = uri.path

    # Remove leading slash and split path
    path_parts = path.sub(/^\//, "").split("/")
    return nil if path_parts.empty?

    username = path_parts.first

    # Detect platform based on host
    platform_info = case host
    when /github\.com$/
      { platform: "github", platform_name: "GitHub", icon: "github" }
    when /gitlab\.com$/
      { platform: "gitlab", platform_name: "GitLab", icon: "gitlab" }
    when /codeberg\.org$/
      { platform: "codeberg", platform_name: "Codeberg", icon: "codeberg" }
    when /bitbucket\.org$/
      { platform: "bitbucket", platform_name: "Bitbucket", icon: "bitbucket" }
    when /sr\.ht$/, /git\.sr\.ht$/
      { platform: "sourcehut", platform_name: "SourceHut", icon: "sourcehut" }
    else
      # Generic git hosting
      { platform: "git", platform_name: host, icon: "git" }
    end

    platform_info.merge(username: username)
  end

  # Fetch platform contribution stats for a user
  # Returns formatted string for display or nil if unavailable
  # Example: "31 contributions" or "org repo"
  def fetch_platform_contributions(platform, username)
    return nil if platform.blank? || username.blank?

    result = Admin::ReviewPlatformService.fetch_contributions(platform, username)

    if result[:error]
      case result[:error]
      when :org_repo
        "org repo"
      else
        nil # Hide count for other errors (timeout, unsupported, etc.)
      end
    elsif result[:total]
      pluralize(result[:total], "contribution")
    else
      nil
    end
  end

  # Fetch full platform contribution data for calendar visualization
  # Returns hash with :contributions array and :total, or nil if unavailable
  # Example: { contributions: [{date: "2024-01-01", count: 5}, ...], total: 365 }
  def fetch_platform_contribution_data(platform, username)
    return nil if platform.blank? || username.blank?

    result = Admin::ReviewPlatformService.fetch_contributions(platform, username)

    if result[:error]
      nil # Hide data for errors
    elsif result[:contributions] && result[:total]
      {
        contributions: result[:contributions],
        total: result[:total]
      }
    else
      nil
    end
  end
end
