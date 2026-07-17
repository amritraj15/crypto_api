class AddCurrencyToCryptoPrices < ActiveRecord::Migration[6.1]
  def change
    add_column :crypto_prices, :currency, :string, null: false, default: 'usd'

    remove_index :crypto_prices, :symbol
    add_index :crypto_prices, %i[symbol currency], unique: true
  end
end
