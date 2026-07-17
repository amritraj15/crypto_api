# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2026_07_17_000004) do

  create_table "crypto_prices", force: :cascade do |t|
    t.string "symbol", null: false
    t.decimal "price", precision: 20, scale: 8, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "currency", default: "usd", null: false
    t.decimal "market_cap", precision: 20, scale: 8
    t.decimal "volume_24h", precision: 20, scale: 8
    t.decimal "price_change_24h", precision: 20, scale: 8
    t.datetime "provider_updated_at"
    t.index ["symbol", "currency"], name: "index_crypto_prices_on_symbol_and_currency", unique: true
  end

end
