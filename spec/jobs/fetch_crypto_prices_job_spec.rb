require 'rails_helper'

RSpec.describe FetchCryptoPricesJob, type: :job do
  before { Rails.cache.clear }

  describe '#perform' do
    it 'fetches all requested symbols in a single CoinGecko request' do
      client = instance_double(CoingeckoClient, fetch_prices: { 'bitcoin' => 65000.5, 'ethereum' => 3400.25 })
      expect(CoingeckoClient).to receive(:new).with(%w[bitcoin ethereum], 'usd').once.and_return(client)

      described_class.perform_now(%w[bitcoin ethereum])

      expect(PriceRepository.find('bitcoin', 'usd').price.to_f).to eq(65000.5)
      expect(PriceRepository.find('ethereum', 'usd').price.to_f).to eq(3400.25)
    end

    it 'defaults to the configured supported symbols when none is given' do
      allow(CryptocurrencyProvider).to receive(:supported).and_return(%w[bitcoin ethereum])
      allow(CoingeckoClient).to receive(:new).and_return(
        instance_double(CoingeckoClient, fetch_prices: %w[bitcoin ethereum].index_with { 100.0 })
      )

      described_class.perform_now

      %w[bitcoin ethereum].each do |symbol|
        expect(PriceRepository.find(symbol, 'usd').price.to_f).to eq(100.0)
      end
    end

    it 'skips symbols that fail SymbolValidator format checks before calling CoinGecko' do
      expect(CoingeckoClient).to receive(:new).with(['bitcoin'], 'usd').and_return(
        instance_double(CoingeckoClient, fetch_prices: { 'bitcoin' => 65000.5 })
      )

      described_class.perform_now(['bitcoin', 'not valid!', ''])

      expect(PriceRepository.find('bitcoin', 'usd')).not_to be_nil
    end

    it 'groups symbols by currency and fetches each currency in bulk' do
      usd_client = instance_double(CoingeckoClient, fetch_prices: { 'bitcoin' => 65000.5, 'ethereum' => 3400.25 })
      eur_client = instance_double(CoingeckoClient, fetch_prices: { 'dogecoin' => 0.25 })

      expect(CoingeckoClient).to receive(:new).with(%w[bitcoin ethereum], 'usd').and_return(usd_client)
      expect(CoingeckoClient).to receive(:new).with(%w[dogecoin], 'eur').and_return(eur_client)

      described_class.perform_now([
        { 'symbol' => 'bitcoin', 'currency' => 'usd' },
        { 'symbol' => 'ethereum', 'currency' => 'usd' },
        { 'symbol' => 'dogecoin', 'currency' => 'eur' }
      ])

      expect(PriceRepository.find('bitcoin', 'usd').price.to_f).to eq(65000.5)
      expect(PriceRepository.find('ethereum', 'usd').price.to_f).to eq(3400.25)
      expect(PriceRepository.find('dogecoin', 'eur').price.to_f).to eq(0.25)
    end

    context 'fallback logic: when CoinGecko does not return a price for a symbol' do
      it 'does not overwrite the previously stored price' do
        PriceStore.write('bitcoin', 65000.5) # simulate a prior successful fetch

        allow(CoingeckoClient).to receive(:new).with(['bitcoin'], 'usd').and_return(
          instance_double(CoingeckoClient, fetch_prices: {})
        )

        described_class.perform_now(['bitcoin'])

        expect(PriceRepository.find('bitcoin', 'usd').price.to_f).to eq(65000.5)
      end

      it 'leaves the DB and cache empty if there was never a prior successful fetch' do
        allow(CoingeckoClient).to receive(:new).with(['bitcoin'], 'usd').and_return(
          instance_double(CoingeckoClient, fetch_prices: {})
        )

        described_class.perform_now(['bitcoin'])

        expect(PriceRepository.find('bitcoin', 'usd')).to be_nil
        expect(PriceCache.read('bitcoin', currency: 'usd')).to be_nil
      end
    end

    context 'when the whole batch request fails (CoingeckoClient::Error)' do
      it 'does not raise and leaves existing prices untouched' do
        PriceStore.write('bitcoin', 65000.5)

        allow(CoingeckoClient).to receive(:new).and_return(
          instance_double(CoingeckoClient).tap { |c| allow(c).to receive(:fetch_prices).and_raise(CoingeckoClient::Error, 'down') }
        )

        expect { described_class.perform_now(['bitcoin']) }.not_to raise_error
        expect(PriceRepository.find('bitcoin', 'usd').price.to_f).to eq(65000.5)
      end
    end

    context 'when persisting one symbol raises unexpectedly' do
      it 'still persists the remaining symbols' do
        allow(CoingeckoClient).to receive(:new).and_return(
          instance_double(CoingeckoClient, fetch_prices: { 'bitcoin' => 65000.5, 'ethereum' => 3400.25 })
        )
        allow(PriceStore).to receive(:write).with('bitcoin', 65000.5, currency: 'usd').and_raise(StandardError, 'boom')
        allow(PriceStore).to receive(:write).with('ethereum', 3400.25, currency: 'usd').and_call_original

        expect { described_class.perform_now(%w[bitcoin ethereum]) }.not_to raise_error
        expect(PriceRepository.find('ethereum', 'usd').price.to_f).to eq(3400.25)
      end
    end

    it 'does not raise when perform receives no valid symbols at all' do
      expect { described_class.perform_now(['not valid!']) }.not_to raise_error
    end

    it 'is enqueued on the default queue' do
      expect(described_class.new.queue_name).to eq('default')
    end
  end
end
