# Ensures the currency parameter used in requests and stored prices is
# well-formed before it reaches CoinGecko or the database.
class CurrencyValidator
  FORMAT = /\A[a-z0-9\-]{1,10}\z/.freeze

  class << self
    def valid?(currency)
      currency.to_s.downcase.match?(FORMAT)
    end

    def filter(currencies)
      Array(currencies).map { |c| c.to_s.downcase }.select { |c| valid?(c) }
    end
  end
end
