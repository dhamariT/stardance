module User::StateFlags
  extend ActiveSupport::Concern

  DISMISSIBLE_THINGS = %w[home_intro flagship_ad shop_suggestion_box willsbuilds_banner].freeze

  # Use symbols here; `tutorial_steps_completed` is the raw persisted array.
  def tutorial_steps = tutorial_steps_completed&.map(&:to_sym) || []

  def tutorial_step_completed?(slug) = tutorial_steps.include?(slug)

  def complete_tutorial_step!(slug)
    append_array_value_once(:tutorial_steps_completed, slug.to_s)
  end

  def revoke_tutorial_step!(slug)
    remove_array_value(:tutorial_steps_completed, slug.to_s)
  end

  def has_dismissed?(thing_name) = things_dismissed.include?(thing_name.to_s)

  def dismiss_thing!(thing_name)
    thing_name_str = thing_name.to_s
    raise ArgumentError, "Invalid thing to dismiss: #{thing_name_str}" unless DISMISSIBLE_THINGS.include?(thing_name_str)

    append_array_value_once(:things_dismissed, thing_name_str)
  end

  def undismiss_thing!(thing_name)
    thing_name_str = thing_name.to_s
    raise ArgumentError, "Invalid thing to dismiss: #{thing_name_str}" unless DISMISSIBLE_THINGS.include?(thing_name_str)

    remove_array_value(:things_dismissed, thing_name_str)
  end

  def should_show_shop_tutorial?
    tutorial_step_completed?(:first_login) && !tutorial_step_completed?(:free_stickers)
  end

  def onboarded? = onboarded_at.present?
  def hca_linked? = hack_club_identity.present?
  def guest? = !hca_linked?

  # True for guests who already started the first-project setup flow and own
  # a project that is gated behind finishing HCA link. Used to swap the
  # "Create your first project" banner copy and to redirect away from the
  # project show page.
  def has_pending_setup_project? = guest? && projects.exists?

  private
    def append_array_value_once(column, value)
      values = public_send(column) || []
      return if values.include?(value)

      updated = case column.to_sym
      when :tutorial_steps_completed
        self.class.where(id: id)
          .where.not("tutorial_steps_completed @> ARRAY[?]::varchar[]", value)
          .update_all([ "tutorial_steps_completed = array_append(tutorial_steps_completed, ?), updated_at = NOW()", value ])
      when :things_dismissed
        self.class.where(id: id)
          .where.not("things_dismissed @> ARRAY[?]::varchar[]", value)
          .update_all([ "things_dismissed = array_append(things_dismissed, ?), updated_at = NOW()", value ])
      else
        raise ArgumentError, "unknown array column #{column.inspect}"
      end
      return false if updated.zero?

      public_send("#{column}=", values + [ value ])
      true
    end

    def remove_array_value(column, value)
      values = public_send(column) || []
      return unless values.include?(value)

      case column.to_sym
      when :tutorial_steps_completed
        self.class.where(id: id)
          .update_all([ "tutorial_steps_completed = array_remove(tutorial_steps_completed, ?), updated_at = NOW()", value ])
      when :things_dismissed
        self.class.where(id: id)
          .update_all([ "things_dismissed = array_remove(things_dismissed, ?), updated_at = NOW()", value ])
      else
        raise ArgumentError, "unknown array column #{column.inspect}"
      end
      public_send("#{column}=", values - [ value ])
      true
    end
end
