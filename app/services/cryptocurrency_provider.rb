class CryptocurrencyProvider
  def self.supported
    Rails.application.config_for(:cryptocurrencies).fetch("supported", [])
  end
end
