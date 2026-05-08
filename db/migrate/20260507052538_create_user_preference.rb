class CreateUserPreference < ActiveRecord::Migration[8.1]
  def change
    create_table :user_preferences do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.boolean :send_votes_to_slack, null: false, default: false
      t.boolean :leaderboard_optin, null: false, default: false
      t.boolean :stardust_balance_notifications, null: false, default: false
      t.boolean :send_notifications_for_followed_projects, null: false, default: true
      t.boolean :send_notifications_for_followed_users, null: false, default: true
      t.boolean :send_notifications_for_new_followers, null: false, default: true
      t.boolean :send_notifications_for_new_comments, null: false, default: true
      t.boolean :search_engine_indexing_off, null: false, default: false

      t.timestamps
    end

    add_index :user_preferences, :leaderboard_optin
  end
end
