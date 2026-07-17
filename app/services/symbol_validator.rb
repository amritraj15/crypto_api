# Guards both the controller (bad param) and the job (bad supported-symbol
# entry or ad hoc perform_now argument) from ever reaching CoinGecko with a
# malformed symbol — no point spending an API call on something that can't
# possibly be a valid coin id.
class SymbolValidator
  FORMAT = /\A[a-z0-9\-]{1,64}\z/.freeze

  class << self
    def valid?(symbol)
      symbol.to_s.downcase.match?(FORMAT)
    end

    # Returns only the symbols that pass the format check, preserving order.
    def filter(symbols)
      Array(symbols).map { |s| s.to_s.downcase }.select { |s| valid?(s) }
    end
  end
end
