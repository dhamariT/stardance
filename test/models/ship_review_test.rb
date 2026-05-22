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
require "test_helper"

class ShipReviewTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @project = projects(:one)
    @reviewer = users(:one)
  end

  def with_owner_and_ship_event
    owner = users(:two)
    owner.update_column(:slack_id, "U_OWNER") if owner.slack_id.blank?
    Project::Membership.find_or_create_by!(project: @project, user: owner) { |m| m.role = :owner }
    ship_event = Post::ShipEvent.new(body: "test ship")
    ship_event.save!(validate: false)
    @project.posts.create!(user: owner, postable: ship_event)
    [ owner, ship_event ]
  end

  test "available_for returns pending reviews with no live claim" do
    review = ShipReview.create!(project: @project, status: :pending)
    assert_includes ShipReview.available_for(@reviewer), review
  end

  test "available_for excludes reviews claimed by another reviewer" do
    other = users(:two)
    review = ShipReview.create!(project: @project, status: :pending,
                                reviewer: other, claim_expires_at: 5.minutes.from_now)
    refute_includes ShipReview.available_for(@reviewer), review
  end

  test "available_for includes reviews claimed by self" do
    review = ShipReview.create!(project: @project, status: :pending,
                                reviewer: @reviewer, claim_expires_at: 5.minutes.from_now)
    assert_includes ShipReview.available_for(@reviewer), review
  end

  test "available_for includes expired claims regardless of holder" do
    other = users(:two)
    review = ShipReview.create!(project: @project, status: :pending,
                                reviewer: other, claim_expires_at: 1.minute.ago)
    assert_includes ShipReview.available_for(@reviewer), review
  end

  test "atomic_claim assigns reviewer and expiry" do
    review = ShipReview.create!(project: @project, status: :pending)
    claimed = ShipReview.atomic_claim!(review.id, @reviewer)
    assert claimed
    assert_equal @reviewer.id, claimed.reviewer_id
    assert claimed.claim_expires_at > Time.current
  end

  test "atomic_claim returns nil when another reviewer holds an active claim" do
    other = users(:two)
    review = ShipReview.create!(project: @project, status: :pending,
                                reviewer: other, claim_expires_at: 5.minutes.from_now)
    assert_nil ShipReview.atomic_claim!(review.id, @reviewer)
  end

  test "release_all_for clears active claims for the user" do
    review = ShipReview.create!(project: @project, status: :pending,
                                reviewer: @reviewer, claim_expires_at: 5.minutes.from_now)
    ShipReview.release_all_for(@reviewer)
    assert_nil review.reload.reviewer_id
    assert_nil review.claim_expires_at
  end

  test "approving the review transitions the project via AASM" do
    @project.update!(ship_status: :submitted)
    review = ShipReview.create!(project: @project, status: :pending)
    review.update!(status: :approved, reviewer: @reviewer, feedback: "looks great")
    assert_equal "approved", @project.reload.ship_status
  end

  test "returning the review sends the project to needs_changes" do
    @project.update!(ship_status: :under_review)
    review = ShipReview.create!(project: @project, status: :pending)
    review.update!(status: :returned, reviewer: @reviewer, feedback: "needs work")
    assert_equal "needs_changes", @project.reload.ship_status
  end

  test "user can re-ship after needs_changes" do
    @project.update!(ship_status: :needs_changes)
    assert @project.may_submit_for_review?, "needs_changes projects must be able to re-submit"
  end

  test "submit_for_review creates a pending ShipReview" do
    project = Project.new(@project.attributes.except("id", "created_at", "updated_at", "ship_status"))
    project.ship_status = :draft
    project.save!(validate: false)
    project.define_singleton_method(:shippable?) { true }

    assert_difference -> { project.ship_reviews.pending.count }, 1 do
      project.submit_for_review!
    end
  end

  test "submit_for_review does not double-create a pending ShipReview" do
    @project.update!(ship_status: :needs_changes)
    @project.define_singleton_method(:shippable?) { true }
    ShipReview.create!(project: @project, status: :pending)

    assert_no_difference -> { @project.ship_reviews.pending.count } do
      @project.submit_for_review!
    end
  end

  test "approving flips the last ship event certification to approved" do
    _owner, ship_event = with_owner_and_ship_event
    @project.update!(ship_status: :submitted)
    review = ShipReview.create!(project: @project, status: :pending)

    review.update!(status: :approved, reviewer: @reviewer)

    assert_equal "approved", ship_event.reload.certification_status
  end

  test "returning does not change ship event certification" do
    _owner, ship_event = with_owner_and_ship_event
    ship_event.update_column(:certification_status, "pending")
    @project.update!(ship_status: :under_review)
    review = ShipReview.create!(project: @project, status: :pending)

    review.update!(status: :returned, reviewer: @reviewer, feedback: "fix the demo")

    assert_equal "pending", ship_event.reload.certification_status
  end

  test "approving enqueues a Slack DM to the owner" do
    owner, _ship_event = with_owner_and_ship_event
    @project.update!(ship_status: :submitted)
    review = ShipReview.create!(project: @project, status: :pending)

    assert_enqueued_with(job: SendSlackDmJob, args: ->(args) { args.first == owner.slack_id }) do
      review.update!(status: :approved, reviewer: @reviewer)
    end
  end

  test "returning enqueues a Slack DM with the feedback" do
    owner, _ship_event = with_owner_and_ship_event
    @project.update!(ship_status: :under_review)
    review = ShipReview.create!(project: @project, status: :pending)

    assert_enqueued_with(job: SendSlackDmJob, args: ->(args) {
      args.first == owner.slack_id && args[1].include?("fix the demo")
    }) do
      review.update!(status: :returned, reviewer: @reviewer, feedback: "fix the demo")
    end
  end

  test "pending review does not enqueue a DM" do
    with_owner_and_ship_event

    assert_no_enqueued_jobs(only: SendSlackDmJob) do
      ShipReview.create!(project: @project, status: :pending)
    end
  end

  test "skips DM when owner has no slack_id" do
    owner = users(:two)
    owner.update_column(:slack_id, nil)
    Project::Membership.find_or_create_by!(project: @project, user: owner) { |m| m.role = :owner }
    @project.update!(ship_status: :submitted)
    review = ShipReview.create!(project: @project, status: :pending)

    assert_no_enqueued_jobs(only: SendSlackDmJob) do
      review.update!(status: :approved, reviewer: @reviewer)
    end
  end
end
