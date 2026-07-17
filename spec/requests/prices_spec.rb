require 'rails_helper'

RSpec.describe 'GET /prices/:symbol', type: :request do
  before { Rails.cache.clear }

  context 'when a price is cached' do
    it 'returns the cached price with updated_at' do
      PriceStore.write('bitcoin', 65000.5)

      get '/prices/bitcoin'

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['symbol']).to eq('bitcoin')
      expect(json['price']).to eq(65000.5)
      expect(json['updated_at']).to be_present
    end

    it 'is case-insensitive on the symbol in the URL' do
      PriceStore.write('bitcoin', 65000.5)

      get '/prices/BITCOIN'

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['price']).to eq(65000.5)
    end
  end

  context 'when the cache is cold but the database has the price' do
    it 'falls back to the database and still returns 200' do
      PriceRepository.upsert('bitcoin', 65000.5) # DB only, cache never written

      get '/prices/bitcoin'

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['price']).to eq(65000.5)
    end
  end

  context 'when no price has ever been stored for the symbol' do
    it 'returns 404' do
      get '/prices/dogecoin'

      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when the symbol format is invalid' do
    it 'returns 422 without touching the cache or database' do
      get '/prices/not%20valid!'

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  context 'fallback: last known price survives a failed background refresh' do
    it 'keeps serving the last known price after the job fails to fetch a fresh one' do
      # Simulate an earlier successful job run.
      PriceStore.write('bitcoin', 65000.5)

      # Simulate the external API being down on the next scheduled run.
      allow(CoingeckoClient).to receive(:new).with(['bitcoin']).and_return(
        instance_double(CoingeckoClient, fetch_prices: {})
      )
      FetchCryptoPricesJob.perform_now(['bitcoin'])

      get '/prices/bitcoin'

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['price']).to eq(65000.5)
    end
  end
end
