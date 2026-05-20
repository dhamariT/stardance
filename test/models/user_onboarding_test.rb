require "test_helper"

class UserOnboardingTest < ActiveSupport::TestCase
  test "valid when interests are all in ALLOWED_INTERESTS" do
    u = User.new(slack_id: "U_VALID_#{SecureRandom.hex(4)}", display_name: "Valid", interests: %w[web_dev hardware])
    u.valid?
    assert_empty u.errors[:interests]
  end

  test "invalid when interests contain values outside ALLOWED_INTERESTS" do
    u = User.new(slack_id: "U_INVALID_#{SecureRandom.hex(4)}", display_name: "Invalid", interests: %w[web_dev hacking_the_planet])
    refute u.valid?
    assert u.errors[:interests].any? { |msg| msg.include?("hacking_the_planet") }
  end

  test "valid when interests is exactly the don't-know sentinel" do
    u = User.new(slack_id: "U_DK_#{SecureRandom.hex(4)}", display_name: "Skipper", interests: [ User::INTERESTS_UNKNOWN ])
    u.valid?
    assert_empty u.errors[:interests]
  end

  test "onboarded? is false when onboarded_at is nil" do
    refute User.new.onboarded?
  end

  test "onboarded? is true when onboarded_at is set" do
    u = User.new(onboarded_at: Time.current)
    assert u.onboarded?
  end

  test "guest? is true when no hack_club_identity" do
    u = User.new
    assert u.guest?
    refute u.hca_linked?
  end

  test "age_attestation enum exposes predicates" do
    u = User.new(age_attestation: "teen_13_18")
    assert u.age_attestation_teen_13_18?
    refute u.age_attestation_ineligible?
  end

  test "experience_level enum exposes predicates" do
    u = User.new(experience_level: "some")
    assert u.experience_some?
    refute u.experience_none?
  end
end
