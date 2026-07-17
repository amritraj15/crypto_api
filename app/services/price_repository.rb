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
    def upsert(symbol = nil, price = nil, currency: PriceStore::DEFAULT_CURRENCY, market_cap: nil, volume_24h: nil, price_change_24h: nil, provider_updated_at: nil, **kwargs)
      attrs = normalize_attrs(symbol, price, currency, market_cap, volume_24h, price_change_24h, provider_updated_at, kwargs)

      now = Time.current
      CryptoPrice.upsert_all(
        [{
          symbol: attrs[:symbol].to_s.downcase,
          currency: attrs[:currency].to_s.downcase,
          price: attrs[:price],
          market_cap: attrs[:market_cap],
          volume_24h: attrs[:volume_24h],
          price_change_24h: attrs[:price_change_24h],
          provider_updated_at: attrs[:provider_updated_at],
          created_at: now,
          updated_at: now
        }],
        unique_by: %i[symbol currency]
      )
      find(attrs[:symbol], attrs[:currency])
    end

    def find(symbol, currency = PriceStore::DEFAULT_CURRENCY)
      CryptoPrice.find_by(symbol: symbol.to_s.downcase, currency: currency.to_s.downcase)
    end

    private

    def normalize_attrs(symbol, price, currency, market_cap, volume_24h, price_change_24h, provider_updated_at, kwargs)
      if symbol.is_a?(Hash)
        attrs = symbol
        symbol = attrs[:symbol] || attrs['symbol'] || kwargs[:symbol]
        price = attrs[:price] || attrs['price'] || kwargs[:price]
        currency = attrs[:currency] || attrs['currency'] || kwargs[:currency] || currency
        market_cap = attrs[:market_cap] || attrs['market_cap'] || kwargs[:market_cap] || market_cap
        volume_24h = attrs[:volume_24h] || attrs['volume_24h'] || kwargs[:volume_24h] || volume_24h
        price_change_24h = attrs[:price_change_24h] || attrs['price_change_24h'] || kwargs[:price_change_24h] || price_change_24h
        provider_updated_at = attrs[:provider_updated_at] || attrs['provider_updated_at'] || kwargs[:provider_updated_at] || provider_updated_at
      elsif kwargs.present?
        symbol = kwargs[:symbol] || symbol
        price = kwargs[:price] || price
        currency = kwargs[:currency] || currency
        market_cap = kwargs[:market_cap] || market_cap
        volume_24h = kwargs[:volume_24h] || volume_24h
        price_change_24h = kwargs[:price_change_24h] || price_change_24h
        provider_updated_at = kwargs[:provider_updated_at] || provider_updated_at
      end

      {
        symbol: symbol,
        price: price,
        currency: currency,
        market_cap: market_cap,
        volume_24h: volume_24h,
        price_change_24h: price_change_24h,
        provider_updated_at: provider_updated_at
      }
    end
  end
end
