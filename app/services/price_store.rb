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
  class << self
    def write(symbol, price)
      record = PriceRepository.upsert(symbol, price)
      PriceCache.write(symbol, serialize(record))
      record
    end

    # Returns { symbol:, price:, updated_at: } or nil if there's no price
    # for this symbol anywhere (neither cache nor DB has ever seen it).
    def read(symbol)
      PriceCache.read(symbol) || read_through_db(symbol)
    end

    private

    def read_through_db(symbol)
      record = PriceRepository.find(symbol)
      return nil unless record

      payload = serialize(record)
      PriceCache.write(symbol, payload)
      payload
    end

    def serialize(record)
      {
        symbol: record.symbol,
        price: record.price.to_f,
        updated_at: record.updated_at.iso8601
      }
    end
  end
end
