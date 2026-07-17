# Wraps all reads/writes to the crypto_prices table (the source of truth).
# Nothing else in the app should call CryptoPrice directly — that keeps the
# persistence layer swappable and gives us one place to reason about
# concurrency.
class PriceRepository
  class << self
    # Upserts via a single atomic SQL statement (INSERT ... ON CONFLICT
    # symbol DO UPDATE) rather than find_or_initialize_by + save.
    #
    # Why: two FetchCryptoPricesJob runs can overlap (a slow run plus the
    # next minute's scheduled run), and both may be writing the same
    # symbol. A read-then-write (find_or_initialize_by/save) has a race
    # window between the read and the write where both processes could
    # decide "no row exists yet" and both try to INSERT — which is exactly
    # what the unique index on `symbol` is there to prevent, but it would
    # surface as an ActiveRecord::RecordNotUnique crash instead of a clean
    # update. upsert_all pushes the conflict resolution down to the
    # database, which handles it atomically.
    def upsert(symbol, price)
      now = Time.current
      CryptoPrice.upsert_all(
        [{ symbol: symbol.to_s.downcase, price: price, created_at: now, updated_at: now }],
        unique_by: :symbol
      )
      find(symbol)
    end

    def find(symbol)
      CryptoPrice.find_by(symbol: symbol.to_s.downcase)
    end
  end
end
