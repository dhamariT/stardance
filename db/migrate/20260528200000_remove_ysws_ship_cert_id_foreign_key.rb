class RemoveYswsShipCertIdForeignKey < ActiveRecord::Migration[7.2]
  def up
    # Remove the old foreign key constraint that incorrectly points to post_ship_events
    # This is safe to run while the app is running since we're just removing a constraint
    if foreign_key_exists?(:certification_ysws_reviews, column: :ship_cert_id)
      remove_foreign_key :certification_ysws_reviews, column: :ship_cert_id
    end
  end

  def down
    # Restore the old (incorrect) foreign key to post_ship_events
    # Note: This may fail if there are ship_cert_id values that don't exist in post_ship_events
    add_foreign_key :certification_ysws_reviews, :post_ship_events, column: :ship_cert_id
  end
end
