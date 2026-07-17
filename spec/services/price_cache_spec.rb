require 'rails_helper'

RSpec.describe PriceCache do
  before { Rails.cache.clear }

  describe '.write and .read' do
    it 'round-trips a payload for a symbol' do
      payload = { symbol: 'bitcoin', price: 65000.5, updated_at: Time.current.iso8601 }
      described_class.write('bitcoin', payload)

      expect(described_class.read('bitcoin')).to eq(payload)
    end

    it 'returns nil for a symbol that has never been cached' do
      expect(described_class.read('doesnotexist')).to be_nil
    end

    it 'keeps different symbols independent' do
      described_class.write('bitcoin', { symbol: 'bitcoin', price: 65000.5 })
      described_class.write('ethereum', { symbol: 'ethereum', price: 3400.25 })

      expect(described_class.read('bitcoin')[:price]).to eq(65000.5)
      expect(described_class.read('ethereum')[:price]).to eq(3400.25)
    end

    it 'is case-insensitive on the symbol' do
      described_class.write('Bitcoin', { symbol: 'bitcoin', price: 65000.5 })

      expect(described_class.read('bitcoin')).not_to be_nil
      expect(described_class.read('BITCOIN')).not_to be_nil
    end
  end

  describe '.write overwriting an existing value' do
    it 'replaces the previous cached payload' do
      described_class.write('bitcoin', { symbol: 'bitcoin', price: 65000.5 })
      described_class.write('bitcoin', { symbol: 'bitcoin', price: 66000.0 })

      expect(described_class.read('bitcoin')[:price]).to eq(66000.0)
    end
  end

  describe 'expiry' do
    it 'expires the entry after PriceCache::EXPIRES_IN' do
      described_class.write('bitcoin', { symbol: 'bitcoin', price: 65000.5 })

      travel_to(Time.current + PriceCache::EXPIRES_IN + 1.second) do
        expect(described_class.read('bitcoin')).to be_nil
      end
    end

    it 'is still readable just before expiry' do
      described_class.write('bitcoin', { symbol: 'bitcoin', price: 65000.5 })

      travel_to(Time.current + PriceCache::EXPIRES_IN - 5.seconds) do
        expect(described_class.read('bitcoin')).not_to be_nil
      end
    end
  end

  describe '.cache_key' do
    it 'namespaces the key by symbol and currency' do
      expect(described_class.cache_key('bitcoin', 'usd')).to eq('crypto_price:bitcoin:usd')
      expect(described_class.cache_key('BTC', 'EUR')).to eq('crypto_price:btc:eur')
    end
  end
end
