module User::Achievements
  extend ActiveSupport::Concern

  def earned_achievement_slugs
    @earned_achievement_slugs ||= achievements.pluck(:achievement_slug).to_set
  end

  def pending_achievement_notifications
    achievements.where(notified: false)
  end

  def recalculate_has_pending_achievements!
    update_column(:has_pending_achievements, achievements.where(notified: false).exists?)
  end

  def earned_achievement?(slug)
    earned_achievement_slugs.include?(slug.to_s)
  end

  def award_achievement!(slug, notified: false)
    return nil if earned_achievement?(slug)

    achievement = ::Achievement.find(slug)
    achievements.create!(achievement_slug: slug.to_s, earned_at: Time.current, notified: notified)
    @earned_achievement_slugs&.add(slug.to_s)
    update_column(:has_pending_achievements, true) unless notified
    achievement
  end

  def check_and_award_achievements!
    ::Achievement.all.each do |achievement|
      award_achievement!(achievement.slug)
    end
  end
end
