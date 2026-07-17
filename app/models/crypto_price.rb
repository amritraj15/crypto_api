class CryptoPrice < ApplicationRecord
  DEFAULT_CURRENCY = Rails.application.config.x.default_currency

  # Columns:
  # - symbol: normalized cryptocurrency identifier (for example, bitcoin)
  # - currency: quote currency for the price (for example, usd)
  # - price: latest price value returned by the provider
  # - market_cap: provider-reported market capitalization
  # - volume_24h: provider-reported 24h trading volume
  # - price_change_24h: provider-reported 24h price change
  # - provider_updated_at: provider timestamp for the latest data point
  # - created_at/updated_at: Rails timestamps
  #
  # The unique index on [:symbol, :currency] is the source of truth for
  # concurrent writes; the validation here is just a fast-fail for normal
  # ActiveRecord create/save.
  validates :symbol, presence: true
  validates :currency, presence: true, format: { with: /\A[a-z0-9\-]{1,10}\z/ }
  validates :price, presence: true, numericality: { greater_than: 0 }
  validates :symbol, uniqueness: { scope: :currency }

  before_validation :normalize_attributes

  private

  def normalize_attributes
    self.symbol = symbol.to_s.downcase if symbol.present?
    self.currency = currency.to_s.downcase.presence || DEFAULT_CURRENCY
  end
end
