class AddMarketMetricsToCryptoPrices < ActiveRecord::Migration[6.1]
  def change
    add_column :crypto_prices, :market_cap, :decimal, precision: 20, scale: 8
    add_column :crypto_prices, :volume_24h, :decimal, precision: 20, scale: 8
    add_column :crypto_prices, :price_change_24h, :decimal, precision: 20, scale: 8
    add_column :crypto_prices, :provider_updated_at, :integer
  end
end
