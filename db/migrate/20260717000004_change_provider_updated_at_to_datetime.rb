class ChangeProviderUpdatedAtToDatetime < ActiveRecord::Migration[6.1]
  def change
    change_column :crypto_prices, :provider_updated_at, :datetime
  end
end
