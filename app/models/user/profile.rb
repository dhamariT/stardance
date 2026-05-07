module User::Profile
  extend ActiveSupport::Concern

  def full_name
    [ first_name, last_name ].compact.join(" ").strip
  end

  def avatar
    "https://cachet.dunkirk.sh/users/#{slack_id}/r"
  end
end
