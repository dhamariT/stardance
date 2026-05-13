require "test_helper"

class ShipReviewTest < ActiveSupport::TestCase
  setup do
    @project = projects(:one)
    @reviewer = users(:one)
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
end
