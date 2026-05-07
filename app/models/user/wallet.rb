module User::Wallet
  extend ActiveSupport::Concern

  def balance = ledger_entries.sum(:amount)

  def cached_balance = Rails.cache.fetch(balance_cache_key) { balance }

  def balance_cache_key = "user/#{id}/sidebar_balance"

  def invalidate_balance_cache! = Rails.cache.delete(balance_cache_key)

  def grant_email
    hcb_email.presence || email
  end
end
