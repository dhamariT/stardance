class ValidateYswsShipCertIdForeignKey < ActiveRecord::Migration[7.2]
  def up
    # Validate the foreign key added in the previous migration
    # This can be done online without blocking writes
    validate_foreign_key :certification_ysws_reviews, :certification_ship_reviews
  end

  def down
    # No-op: validation is a one-way operation
    # If we need to roll back, we'd remove the FK in the previous migration's rollback
  end
end
