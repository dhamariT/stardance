class EventsController < ApplicationController
  before_action :set_body_class

  # The events page lists enabled missions for everyone, and additionally
  # surfaces any missions the current user can manage (admin OR owner) even
  # if they're disabled drafts. This keeps draft missions visible to the
  # people working on them without leaking them publicly. The view tags those
  # cards with a "manageable" border via @manageable_mission_ids.
  def index
    manageable_ids = manageable_mission_ids
    base = Mission.includes(:icon_attachment)

    @missions = if current_user&.admin?
                  # Admins can manage everything — show all non-deleted
                  # missions, enabled or not.
                  base.order(featured_at: :desc, name: :asc)
    elsif manageable_ids.any?
                  # Qualify `missions.id`: `includes(:icon_attachment)` adds
                  # a JOIN to active_storage_attachments which also has an
                  # `id` column, so a bare `id IN (?)` is ambiguous.
                  base.where("missions.enabled = TRUE OR missions.id IN (?)", manageable_ids)
                      .order(featured_at: :desc, name: :asc)
    else
                  base.where(enabled: true).order(featured_at: :desc, name: :asc)
    end

    @manageable_mission_ids = if current_user&.admin?
                                Set.new(@missions.map(&:id))
    else
                                Set.new(manageable_ids)
    end
  end

  private

  # Mission ids the current user owns. Empty Set for anonymous + admins
  # (admins are handled separately because they manage everything).
  def manageable_mission_ids
    return [] unless current_user
    Mission::Membership.where(user_id: current_user.id, role: :owner)
                       .pluck(:mission_id)
  end

  def set_body_class
    @body_class = "app-layout-page"
  end
end
