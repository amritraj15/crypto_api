# Runs every minute (see config/initializers/sidekiq_cron.rb).
#
# Fetches all supported symbols in a single CoinGecko request (cheaper than
# one request per symbol), then persists whatever came back through
# PriceStore (DB first, then cache). A symbol CoinGecko didn't return a
# price for is left untouched — its last known DB/cache value keeps
# serving, which is the fallback behavior the assignment asks for.
class FetchCryptoPricesJob < ApplicationJob
  queue_as :default

  def perform(symbols = nil)
    symbols ||= CryptocurrencyProvider.supported
    requested_items = normalize_requested_items(symbols)
    valid_items = filter_valid_items(requested_items)
    log_invalid_items(requested_items, valid_items)
    return if valid_items.empty?

    valid_items.group_by { |item| item[:currency] }.each do |currency, items|
      symbols_for_currency = items.map { |item| item[:symbol] }.uniq
      prices = fetch(symbols_for_currency, currency)
      next if prices.nil? # whole batch failed for this currency

      persist_all(prices, currency)
      log_missing_symbols(symbols_for_currency, prices.keys, currency)
    end
  rescue => e
    Rails.logger.error(tag("unexpected error: #{e.class}: #{e.message}"))
  end

  private

  def normalize_requested_items(symbols)
    Array(symbols).map do |entry|
      case entry
      when Hash
        {
          symbol: entry[:symbol] || entry['symbol'],
          currency: entry[:currency] || entry['currency'] || PriceStore::DEFAULT_CURRENCY
        }
      else
        { symbol: entry.to_s, currency: PriceStore::DEFAULT_CURRENCY }
      end
    end.map do |item|
      item[:symbol] = item[:symbol].to_s.downcase
      item[:currency] = item[:currency].to_s.downcase.presence || PriceStore::DEFAULT_CURRENCY
      item
    end
  end

  def filter_valid_items(items)
    items.select do |item|
      SymbolValidator.valid?(item[:symbol]) && CurrencyValidator.valid?(item[:currency])
    end
  end

  def fetch(symbols, currency)
    CoingeckoClient.new(symbols, currency).fetch_prices
  rescue CoingeckoClient::Error => e
    Rails.logger.error(tag("CoinGecko request failed for #{symbols.join(',')} #{currency}: #{e.message}"))
    nil
  end

  def persist_all(prices, currency)
    prices.each do |symbol, price|
      begin
        PriceStore.write(symbol, price, currency: currency)
      rescue => e
        Rails.logger.error(tag("failed to persist #{symbol}=#{price} #{currency}: #{e.message}"))
      end
    end
  end

  def log_missing_symbols(requested, returned, currency)
    (requested - returned).each do |symbol|
      Rails.logger.warn(tag("no price returned for #{symbol} #{currency}; keeping last known value"))
    end
  end

  def log_invalid_items(requested_items, valid_items)
    invalid = requested_items - valid_items
    invalid.each do |item|
      Rails.logger.warn(tag("skipping invalid symbol/currency #{item.inspect}"))
    end
  end

  def tag(message)
    "[FetchCryptoPricesJob] #{message}"
  end
end
