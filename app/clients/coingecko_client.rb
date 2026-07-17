require "net/http"
require "json"

# Thin client around CoinGecko's /simple/price endpoint. Deliberately has
# no knowledge of caching, the database, or jobs — its only job is
# "symbols in, prices out (or a raised Error)". Isolating it here means a
# provider swap or response-shape change only ever touches this file.
class CoingeckoClient
  class Error < StandardError; end

  DEFAULT_CURRENCY = 'usd'
  BASE_URI = URI("https://api.coingecko.com/api/v3/simple/price")
  OPEN_TIMEOUT = 3
  READ_TIMEOUT = 3

  def initialize(symbols, currency = DEFAULT_CURRENCY)
    @symbols = Array(symbols).map { |s| s.to_s.downcase }
    @currency = currency.to_s.downcase.presence || DEFAULT_CURRENCY
  end

  # Returns a Hash of { "bitcoin" => 65000.5, "ethereum" => 3400.25 }.
  #
  # Only includes symbols CoinGecko actually returned a price for —
  # a symbol CoinGecko doesn't recognize is just absent from the hash, not
  # an error. Network failures, non-2xx responses, and unparsable bodies
  # raise CoingeckoClient::Error instead, since those mean the *whole*
  # batch is untrustworthy, not just one symbol.
  def fetch_prices
    fetch_price_payloads.transform_values { |payload| payload[:price] }
  end

  def fetch_price_payloads
    return {} if @symbols.empty?

    response = perform_request
    raise Error, "unexpected response status #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    parse(response.body)
  end

  private

  def perform_request
    uri = BASE_URI.dup
    uri.query = URI.encode_www_form(
      ids: @symbols.join(","),
      vs_currencies: @currency,
      include_market_cap: true,
      include_24hr_vol: true,
      include_24hr_change: true,
      include_last_updated_at: true
    )

    Net::HTTP.start(uri.host, uri.port,
                     use_ssl: true,
                     open_timeout: OPEN_TIMEOUT,
                     read_timeout: READ_TIMEOUT) do |http|
      request = Net::HTTP::Get.new(uri)
      request["accept"] = "application/json"
      api_key = ENV["COINGECKO_API_KEY"]
      request["x-cg-demo-api-key"] = api_key if api_key.present?
      http.request(request)
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
    raise Error, "network error: #{e.message}"
  end

  def parse(body)
    JSON.parse(body).each_with_object({}) do |(symbol, data), result|
      price = data.is_a?(Hash) ? data[@currency] : nil
      next unless price.is_a?(Numeric)

      result[symbol] = {
        price: price,
        market_cap: data["#{@currency}_market_cap"],
        volume_24h: data["#{@currency}_24h_vol"],
        price_change_24h: data["#{@currency}_24h_change"],
        provider_updated_at: data["last_updated_at"]
      }
    end
  rescue JSON::ParserError => e
    raise Error, "invalid JSON response: #{e.message}"
  end
end
