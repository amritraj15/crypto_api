require 'rails_helper'

RSpec.describe PriceStore do
  before { Rails.cache.clear }

  describe '.write' do
    it 'persists to the database and mirrors into the cache' do
      described_class.write('bitcoin', 65000.5)

      expect(CryptoPrice.find_by(symbol: 'bitcoin', currency: 'usd').price.to_f).to eq(65000.5)
      expect(PriceCache.read('bitcoin', currency: 'usd')[:price]).to eq(65000.5)
    end

    it 'persists currency-specific prices separately' do
      described_class.write('bitcoin', 65000.5, currency: 'usd')
      described_class.write('bitcoin', 60000.0, currency: 'eur')

      expect(CryptoPrice.find_by(symbol: 'bitcoin', currency: 'usd').price.to_f).to eq(65000.5)
      expect(CryptoPrice.find_by(symbol: 'bitcoin', currency: 'eur').price.to_f).to eq(60000.0)
    end

    it 'includes updated_at in the cached payload' do
      described_class.write('bitcoin', 65000.5)

      expect(PriceCache.read('bitcoin', currency: 'usd')[:updated_at]).to be_present
    end
  end

  describe '.read' do
    it 'reads from the cache when present, without touching the DB' do
      described_class.write('bitcoin', 65000.5)
      expect(PriceRepository).not_to receive(:find)

      expect(described_class.read('bitcoin')[:price]).to eq(65000.5)
    end

    context 'when the cache is cold but the DB has the price (cache miss fallback)' do
      it 'reads through to the database and repopulates the cache' do
        PriceRepository.upsert('bitcoin', 65000.5)
        expect(PriceCache.read('bitcoin', currency: 'usd')).to be_nil # cache was never written directly

        result = described_class.read('bitcoin')

        expect(result[:price]).to eq(65000.5)
        expect(PriceCache.read('bitcoin', currency: 'usd')).not_to be_nil # now repopulated
      end
    end

    context 'when the cache TTL has expired but the DB still has the price' do
      it 'falls back to the database instead of returning nil' do
        described_class.write('bitcoin', 65000.5)

        travel_to(Time.current + PriceCache::EXPIRES_IN + 1.second) do
          expect(PriceCache.read('bitcoin', currency: 'usd')).to be_nil # expired

          result = described_class.read('bitcoin')
          expect(result[:price]).to eq(65000.5) # served from the DB instead
        end
      end
    end

    it 'returns nil when the symbol exists in neither the cache nor the DB' do
      expect(described_class.read('doesnotexist')).to be_nil
    end
  end
end
