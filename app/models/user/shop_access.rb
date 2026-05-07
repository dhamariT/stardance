module User::ShopAccess
  extend ActiveSupport::Concern

  def seller? = ShopItem::HackClubberItem.exists?(user_id: id)

  def has_regions?
    regions.present? && regions.any?
  end

  def has_region?(region_code)
    regions.include?(region_code.to_s.upcase)
  end

  def regions_display
    regions.map { |region| Shop::Regionalizable.region_name(region) }.join(", ")
  end

  def reject_pending_orders!(reason: "User banned")
    shop_orders.where(aasm_state: %w[pending awaiting_periodical_fulfillment]).find_each do |order|
      order.mark_rejected(reason)
      order.save!
    end
  end

  def cancel_shop_order(order_id)
    order = shop_orders.find(order_id)
    return { success: false, error: "Your order can not be canceled" } unless order.may_refund?

    order.with_lock do
      return { success: false, error: "Your order can not be canceled" } unless order.may_refund?

      order.refund!
      order.accessory_orders.each { |accessory_order| accessory_order.refund! if accessory_order.may_refund? }
    end
    { success: true, order: order }
  rescue ActiveRecord::RecordNotFound
    { success: false, error: "wuh" }
  end

  def addresses
    identity = identities.find_by(provider: "hack_club")
    return [] unless identity&.access_token.present?

    identity_payload = HCAService.identity(identity.access_token)
    addresses = identity_payload["addresses"] || []
    phone_number = identity_payload["phone_number"]
    addresses.map { |address| address.merge("phone_number" => phone_number) }
  end

  def birthday
    identity = identities.find_by(provider: "hack_club")
    return nil unless identity&.access_token.present?

    identity_payload = HCAService.identity(identity.access_token)
    birthday_str = identity_payload["birthday"]
    return nil if birthday_str.blank?

    Date.parse(birthday_str)
  rescue ArgumentError
    nil
  end
end
