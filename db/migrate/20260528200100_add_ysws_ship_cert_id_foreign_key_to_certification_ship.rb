class AddYswsShipCertIdForeignKeyToCertificationShip < ActiveRecord::Migration[7.2]
  def up
    # First, set all existing ship_cert_id values to NULL
    # The old values were pointing to post_ship_events.id (incorrect)
    # After this migration, ship_cert_id will point to certification_ship_reviews.id (correct)
    # This is safe because we're just cleaning up incorrect foreign key references
    safety_assured do
      execute "UPDATE certification_ysws_reviews SET ship_cert_id = NULL WHERE ship_cert_id IS NOT NULL"
    end

    # Add the foreign key without validation to avoid locking
    # Will be validated in the next migration
    add_foreign_key :certification_ysws_reviews, :certification_ship_reviews, column: :ship_cert_id, validate: false

    # Note: Future YSWS reviews created via the callback will have the correct ship_cert_id
  end

  def down
    # Remove the new foreign key constraint
    remove_foreign_key :certification_ysws_reviews, :certification_ship_reviews

    # Note: We don't restore the old ship_cert_id values because they were incorrect
    # They would need to be manually backfilled if needed
  end
end
