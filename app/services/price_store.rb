# The only class the job and controller talk to for reading/writing
# prices. It implements the pipeline:
#
#   CoinGecko -> Database (source of truth) -> Redis/Rails.cache -> Controller
#
# Write path: persist to the DB first, then mirror into the cache.
# Read path: try the cache first; on a miss (cold cache, or the TTL
# expired), fall back to the DB and repopulate the cache so the next read
# doesn't need to.
#
# Neither the job nor the controller needs to know that two storage layers
# exist — if the caching strategy or the DB schema changes, this is the
# only file that needs to.
class PriceStore
  DEFAULT_CURRENCY = 'usd'

  class << self
    def write(symbol, price, currency: DEFAULT_CURRENCY, market_cap: nil, volume_24h: nil, price_change_24h: nil, provider_updated_at: nil)
      record = PriceRepository.upsert(
        symbol,
        price,
        currency: currency,
        market_cap: market_cap,
        volume_24h: volume_24h,
        price_change_24h: price_change_24h,
        provider_updated_at: provider_updated_at
      )
      PriceCache.write(symbol, serialize(record), currency: record.currency)
      record
    end

    # Returns { symbol:, currency:, price:, updated_at: } or nil if there's no
    # price for this symbol/currency anywhere.
    def read(symbol, currency: DEFAULT_CURRENCY)
      PriceCache.read(symbol, currency: currency) || read_through_db(symbol, currency)
    end

    private

    def read_through_db(symbol, currency)
      record = PriceRepository.find(symbol, currency)
      return nil unless record

      payload = serialize(record)
      PriceCache.write(symbol, payload, currency: record.currency)
      payload
    end

    def serialize(record)
      {
        symbol: record.symbol,
        currency: record.currency,
        price: record.price.to_f,
        market_cap: record.market_cap&.to_f,
        volume_24h: record.volume_24h&.to_f,
        price_change_24h: record.price_change_24h&.to_f,
        updated_at: record.updated_at.iso8601
      }
    end
  end
end
