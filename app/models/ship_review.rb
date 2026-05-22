# == Schema Information
#
# Table name: ship_reviews
#
#  id               :bigint           not null, primary key
#  claim_expires_at :datetime
#  claimed_at       :datetime
#  decided_at       :datetime
#  feedback         :text
#  internal_reason  :text
#  lock_version     :integer          default(0), not null
#  status           :integer          default("pending"), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  project_id       :bigint           not null
#  reviewer_id      :bigint
#
# Indexes
#
#  index_ship_reviews_on_decided_at                   (decided_at)
#  index_ship_reviews_on_reviewer_id                  (reviewer_id)
#  index_ship_reviews_on_status_and_claim_expires_at  (status,claim_expires_at)
#  index_ship_reviews_unique_pending_project          (project_id) UNIQUE WHERE (status = 0)
#
# Foreign Keys
#
#  fk_rails_...  (project_id => projects.id)
#  fk_rails_...  (reviewer_id => users.id)
#
class ShipReview < ApplicationRecord
  include Reviewable

  belongs_to :project
  belongs_to :reviewer, class_name: "User", optional: true

  has_paper_trail

  enum :status, {
    pending: 0,
    approved: 1,
    returned: 2
  }, default: :pending

  validates :feedback, length: { maximum: 10_000 }, allow_blank: true
  validates :internal_reason, length: { maximum: 10_000 }, allow_blank: true

  scope :for_reviewer, ->(user) {
    joins(:project)
      .where(projects: { deleted_at: nil })
      .where.not(project_id: user.memberships.select(:project_id))
  }

  scope :available_for, ->(user) {
    where(status: statuses[:pending]).where(
      "(reviewer_id IS NULL OR claim_expires_at IS NULL OR claim_expires_at < ?) OR reviewer_id = ?",
      Time.current, user.id
    ).merge(for_reviewer(user))
  }

  before_save :set_decided_at, if: :status_changed?
  after_save :sync_project_state!, if: :saved_change_to_status?
  after_save_commit :notify_owner!, if: -> { saved_change_to_status? && !pending? }
  after_save_commit :create_ysws_review!, if: -> { saved_change_to_status? && approved? }

  private

  def set_decided_at
    self.decided_at = Time.current if !pending? && decided_at.nil?
  end

  def sync_project_state!
    return if pending?
    project.with_lock do
      project.start_review! if project.may_start_review?
      case status.to_sym
      when :approved
        project.approve! if project.may_approve?
        project.last_ship_event&.update!(certification_status: "approved")
      when :returned
        project.return_for_changes! if project.may_return_for_changes?
      end
    end
  end

  def notify_owner!
    owner = project.memberships.owner.first&.user
    return unless owner&.slack_id.present?

    case status.to_sym
    when :approved
      owner.dm_user("Your project '#{project.title}' was approved. It's out for voting now.")
    when :returned
      msg = "Your project '#{project.title}' needs changes before it can ship."
      msg += "\n\n#{feedback}" if feedback.present?
      owner.dm_user(msg)
    end
  end

  def create_ysws_review!
    ship_event = project.last_ship_event
    return unless ship_event

    owner = project.memberships.owner.first&.user
    return unless owner

    # Check if a YSWS review already exists for this ship event
    existing_review = YswsReview.find_by(post_ship_event_id: ship_event.id)
    if existing_review
      # If review was synced to Airtable but not reviewed yet, reset it to appear as new
      if existing_review.airtable_synced_at.nil? && existing_review.reviewed_at.present?
        existing_review.update!(
          reviewed_at: nil,
          reviewer_id: nil
        )
        Rails.logger.info "[ShipReview] Reset YswsReview #{existing_review.id} for Project #{project.id} to appear as new"
      end
      return
    end

    # Calculate total original minutes from ship_event.hours
    # This uses the time between ships (or from project creation for first ship)
    hours_worked = ship_event.hours || 0
    original_minutes = (hours_worked * 60).to_i

    # Create YswsReview
    ysws_review = YswsReview.create!(
      user: owner,
      project: project,
      post_ship_event: ship_event,
      ship_cert: ship_event, # This IS the certification event
      reviewer_id: nil, # Will be assigned by guardian
      original_minutes: original_minutes,
      approved_minutes: nil, # Will be set by YSWS reviewer
      reviewed_at: nil
    )

    # Create DevlogReview for each devlog in the time period
    # Get devlogs between previous ship and this ship
    previous_ship = project.ship_events.where("created_at < ?", ship_event.created_at).order(created_at: :desc).first
    start_time = previous_ship&.created_at || project.created_at

    devlogs_in_period = project.devlogs
      .joins("INNER JOIN posts ON posts.postable_id = post_devlogs.id AND posts.postable_type = 'Post::Devlog'")
      .where("posts.created_at >= ? AND posts.created_at <= ?", start_time, ship_event.created_at)
      .distinct

    devlogs_in_period.each do |devlog|
      DevlogReview.create!(
        post_devlog: devlog,
        ysws_review: ysws_review,
        original_minutes: devlog.duration_seconds / 60,
        approved_minutes: nil, # Will be set by YSWS reviewer
        justification: nil,
        status: "pending"
      )
    end

    Rails.logger.info "[ShipReview] Created YswsReview #{ysws_review.id} for Project #{project.id} with #{devlogs_in_period.count} devlogs"
  rescue => e
    Rails.logger.error "[ShipReview] Failed to create YswsReview for Project #{project.id}: #{e.message}"
    Sentry.capture_exception(e, extra: { ship_review_id: id, project_id: project.id })
  end
end
