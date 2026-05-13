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

  after_save :sync_project_state!, if: :saved_change_to_status?

  private

  def sync_project_state!
    return if pending?
    project.with_lock do
      project.start_review! if project.may_start_review?
      case status.to_sym
      when :approved
        project.approve! if project.may_approve?
      when :rejected
        project.reject! if project.may_reject?
      when :returned
        project.return_for_changes! if project.may_return_for_changes?
      end
    end
  end
end
