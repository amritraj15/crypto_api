class CreateCryptoPrices < ActiveRecord::Migration[6.1]
  def change
    create_table :crypto_prices do |t|
      t.string :symbol, null: false
      t.decimal :price, precision: 20, scale: 8, null: false

      t.timestamps
    end

    # Prevents duplicate rows for the same symbol when two job runs (or a
    # manual perform_now + the scheduled run) race each other — the upsert
    # in PriceRepository relies on this being present.
    add_index :crypto_prices, :symbol, unique: true
  end
end
