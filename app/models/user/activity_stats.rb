module User::ActivityStats
  extend ActiveSupport::Concern

  def has_commented?
    comments.exists?
  end

  def has_shipped?
    projects.joins(:ship_events).exists?
  end

  def shipped_projects_count_in_range(start_date, end_date)
    projects
      .joins(:posts)
      .where(posts: { postable_type: "Post::ShipEvent" })
      .where(posts: { created_at: start_date.beginning_of_day..end_date.end_of_day })
      .distinct
      .count
  end
end
