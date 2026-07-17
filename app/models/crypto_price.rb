class CryptoPrice < ApplicationRecord
  # The unique index (see db/migrate/..._create_crypto_prices.rb) is what
  # actually enforces this under concurrent writes; the validation here is
  # just a fast-fail for anything going through normal AR create/save
  # (PriceRepository's upsert path bypasses validations by design — see
  # its comment for why).
  validates :symbol, presence: true, uniqueness: true
  validates :price, presence: true, numericality: { greater_than: 0 }

  before_validation :normalize_symbol

  private

  def normalize_symbol
    self.symbol = symbol.to_s.downcase if symbol.present?
  end
end
