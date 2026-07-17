# Thin wrapper around Rails.cache — the fast-path layer in front of the
# database. Unlike the original cache-only design, this now has a bounded
# TTL: the database is the source of truth (see PriceRepository), so it's
# safe to let the cache expire — PriceStore falls back to the DB on a
# cache miss and repopulates it. That's what "configure cache expiry"
# below actually buys us, as opposed to the earlier no-TTL version where a
# stale value could sit in the cache forever if the job stopped running.
class PriceCache
  KEY_PREFIX = "crypto_price"

  # Longer than the job's 1-minute cadence (so a single slow/missed run
  # doesn't cause every request to fall through to the DB) but short
  # enough that a cache entry can't outlive the job being broken for very
  # long before reads start hitting PriceRepository directly.
  EXPIRES_IN = 2.minutes

  class << self
    def write(symbol, payload, currency: PriceStore::DEFAULT_CURRENCY)
      Rails.cache.write(cache_key(symbol, currency), payload, expires_in: EXPIRES_IN)
    end

    def read(symbol, currency: PriceStore::DEFAULT_CURRENCY)
      Rails.cache.read(cache_key(symbol, currency))
    end

    def cache_key(symbol, currency = PriceStore::DEFAULT_CURRENCY)
      "#{KEY_PREFIX}:#{symbol.to_s.downcase}:#{currency.to_s.downcase}"
    end
  end
end
