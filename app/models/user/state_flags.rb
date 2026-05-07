module User::StateFlags
  extend ActiveSupport::Concern

  DISMISSIBLE_THINGS = %w[home_intro flagship_ad shop_suggestion_box willsbuilds_banner ai_coding_time_ignored_card].freeze

  # Use symbols here; `tutorial_steps_completed` is the raw persisted array.
  def tutorial_steps = tutorial_steps_completed&.map(&:to_sym) || []

  def tutorial_step_completed?(slug) = tutorial_steps.include?(slug)

  def complete_tutorial_step!(slug)
    return if tutorial_step_completed?(slug)

    updated = self.class.where(id: id)
      .where.not("tutorial_steps_completed @> ARRAY[?]::varchar[]", slug.to_s)
      .update_all([ "tutorial_steps_completed = array_append(tutorial_steps_completed, ?), updated_at = NOW()", slug.to_s ])
    return false if updated.zero?

    self.tutorial_steps_completed = (tutorial_steps_completed || []) + [ slug.to_s ]
    true
  end

  def revoke_tutorial_step!(slug)
    return unless tutorial_step_completed?(slug)

    self.class.where(id: id)
      .update_all([ "tutorial_steps_completed = array_remove(tutorial_steps_completed, ?), updated_at = NOW()", slug.to_s ])
    self.tutorial_steps_completed = (tutorial_steps_completed || []) - [ slug.to_s ]
    true
  end

  def has_dismissed?(thing_name) = things_dismissed.include?(thing_name.to_s)

  def dismiss_thing!(thing_name)
    thing_name_str = thing_name.to_s
    raise ArgumentError, "Invalid thing to dismiss: #{thing_name_str}" unless DISMISSIBLE_THINGS.include?(thing_name_str)
    return if has_dismissed?(thing_name_str)

    updated = self.class.where(id: id)
      .where.not("things_dismissed @> ARRAY[?]::varchar[]", thing_name_str)
      .update_all([ "things_dismissed = array_append(things_dismissed, ?), updated_at = NOW()", thing_name_str ])
    return false if updated.zero?

    self.things_dismissed = (things_dismissed || []) + [ thing_name_str ]
    true
  end

  def undismiss_thing!(thing_name)
    thing_name_str = thing_name.to_s
    raise ArgumentError, "Invalid thing to dismiss: #{thing_name_str}" unless DISMISSIBLE_THINGS.include?(thing_name_str)
    return unless has_dismissed?(thing_name_str)

    update_columns(things_dismissed: things_dismissed - [ thing_name_str ], updated_at: Time.current)
  end

  def should_show_shop_tutorial?
    tutorial_step_completed?(:first_login) && !tutorial_step_completed?(:free_stickers)
  end
end
