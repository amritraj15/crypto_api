# Wraps all reads/writes to the crypto_prices table (the source of truth).
# Nothing else in the app should call CryptoPrice directly — that keeps the
# persistence layer swappable and gives us one place to reason about
# concurrency.
class PriceRepository
  class << self
    # Upserts via a single atomic SQL statement (INSERT ... ON CONFLICT
    # (symbol, currency) DO UPDATE) rather than find_or_initialize_by + save.
    #
    # Why: the same symbol can be tracked in multiple currencies, and two
    # FetchCryptoPricesJob runs can still overlap. The composite unique
    # index and upsert_all's ON CONFLICT DO UPDATE handle this atomically.
    def upsert(symbol, price, currency = PriceStore::DEFAULT_CURRENCY)
      now = Time.current
      CryptoPrice.upsert_all(
        [{ symbol: symbol.to_s.downcase, currency: currency.to_s.downcase, price: price, created_at: now, updated_at: now }],
        unique_by: %i[symbol currency]
      )
      find(symbol, currency)
    end

    def find(symbol, currency = PriceStore::DEFAULT_CURRENCY)
      CryptoPrice.find_by(symbol: symbol.to_s.downcase, currency: currency.to_s.downcase)
    end
  end
end
