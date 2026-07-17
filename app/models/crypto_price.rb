class CryptoPrice < ApplicationRecord
  DEFAULT_CURRENCY = 'usd'

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
