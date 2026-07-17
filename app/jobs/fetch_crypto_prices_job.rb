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
    valid_symbols = SymbolValidator.filter(symbols)
    log_invalid_symbols(symbols, valid_symbols)
    return if valid_symbols.empty?

    prices = fetch(valid_symbols)
    return if prices.nil? # whole batch failed — already logged in #fetch

    persist_all(prices)
    log_missing_symbols(valid_symbols, prices.keys)
  rescue => e
    # Belt-and-braces: everything above already rescues what it expects to
    # rescue, but a job that raises silently drops off Sidekiq's radar
    # until someone checks the dead set. Log loudly instead.
    Rails.logger.error(tag("unexpected error: #{e.class}: #{e.message}"))
  end

  private

  # Returns the prices hash, or nil if the whole batch request failed.
  def fetch(symbols)
    CoingeckoClient.new(symbols).fetch_prices
  rescue CoingeckoClient::Error => e
    Rails.logger.error(tag("CoinGecko request failed for #{symbols.join(',')}: #{e.message}"))
    nil
  end

  def persist_all(prices)
    prices.each do |symbol, price|
      begin
        PriceStore.write(symbol, price)
      rescue => e
        Rails.logger.error(tag("failed to persist #{symbol}=#{price}: #{e.message}"))
      end
    end
  end

  def log_missing_symbols(requested, returned)
    (requested - returned).each do |symbol|
      Rails.logger.warn(tag("no price returned for #{symbol}; keeping last known value"))
    end
  end

  def log_invalid_symbols(requested, valid)
    (Array(requested).map { |s| s.to_s.downcase } - valid).each do |symbol|
      Rails.logger.warn(tag("skipping invalid symbol #{symbol.inspect}"))
    end
  end

  def tag(message)
    "[FetchCryptoPricesJob] #{message}"
  end
end
