require 'rails_helper'

RSpec.describe CoingeckoClient do
  let(:url) { %r{https://api\.coingecko\.com/api/v3/simple/price} }

  describe '#fetch_prices' do
    it 'returns an empty hash without making a request when given no symbols' do
      expect(described_class.new([]).fetch_prices).to eq({})
    end

    it 'fetches multiple symbols in a single request' do
      stub = stub_request(:get, url)
        .with(query: hash_including('ids' => 'bitcoin,ethereum'))
        .to_return(
          status: 200,
          body: { bitcoin: { usd: 65000.5 }, ethereum: { usd: 3400.25 } }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = described_class.new(%w[bitcoin ethereum]).fetch_prices

      expect(result).to eq('bitcoin' => 65000.5, 'ethereum' => 3400.25)
      expect(stub).to have_been_requested.once
    end

    it 'omits symbols CoinGecko did not return a price for, without raising' do
      stub_request(:get, url)
        .to_return(status: 200, body: { bitcoin: { usd: 65000.5 } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      result = described_class.new(%w[bitcoin dogecoin]).fetch_prices

      expect(result).to eq('bitcoin' => 65000.5)
    end

    it 'raises Error on a non-2xx response' do
      stub_request(:get, url).to_return(status: 500, body: 'internal error')

      expect { described_class.new(%w[bitcoin]).fetch_prices }.to raise_error(CoingeckoClient::Error)
    end

    it 'raises Error on a 429 rate limit response' do
      stub_request(:get, url).to_return(status: 429, body: 'rate limited')

      expect { described_class.new(%w[bitcoin]).fetch_prices }.to raise_error(CoingeckoClient::Error)
    end

    it 'raises Error when the response body is not valid JSON' do
      stub_request(:get, url).to_return(status: 200, body: 'not json')

      expect { described_class.new(%w[bitcoin]).fetch_prices }.to raise_error(CoingeckoClient::Error)
    end

    it 'raises Error when the connection times out' do
      stub_request(:get, url).to_timeout

      expect { described_class.new(%w[bitcoin]).fetch_prices }.to raise_error(CoingeckoClient::Error)
    end

    it 'raises Error when the connection is refused' do
      stub_request(:get, url).to_raise(Errno::ECONNREFUSED)

      expect { described_class.new(%w[bitcoin]).fetch_prices }.to raise_error(CoingeckoClient::Error)
    end

    it 'ignores a malformed entry (non-hash value) for one symbol without failing the batch' do
      stub_request(:get, url)
        .to_return(status: 200, body: { bitcoin: 'oops', ethereum: { usd: 3400.25 } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      result = described_class.new(%w[bitcoin ethereum]).fetch_prices

      expect(result).to eq('ethereum' => 3400.25)
    end

    it 'sends the API key header when COINGECKO_API_KEY is set' do
      stub = stub_request(:get, url)
        .with(headers: { 'x-cg-demo-api-key' => 'test-key-123' })
        .to_return(status: 200, body: { bitcoin: { usd: 65000.5 } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('COINGECKO_API_KEY').and_return('test-key-123')

      described_class.new(%w[bitcoin]).fetch_prices

      expect(stub).to have_been_requested
    end

    it 'downcases symbols before querying' do
      stub_request(:get, url)
        .to_return(status: 200, body: { bitcoin: { usd: 65000.5 } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect(described_class.new(%w[BITCOIN]).fetch_prices).to eq('bitcoin' => 65000.5)
    end
  end
end
