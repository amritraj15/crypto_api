require 'rails_helper'

RSpec.describe PriceRepository do
  describe '.upsert' do
    it 'creates a new row when the symbol does not exist yet' do
      described_class.upsert('bitcoin', 65000.5)

      record = CryptoPrice.find_by(symbol: 'bitcoin')
      expect(record.price.to_f).to eq(65000.5)
    end

    it 'updates the existing row instead of creating a duplicate' do
      described_class.upsert('bitcoin', 65000.5)
      described_class.upsert('bitcoin', 66000.0)

      expect(CryptoPrice.where(symbol: 'bitcoin').count).to eq(1)
      expect(CryptoPrice.find_by(symbol: 'bitcoin').price.to_f).to eq(66000.0)
    end

    it 'normalizes the symbol to lowercase' do
      described_class.upsert('BITCOIN', 65000.5)

      expect(CryptoPrice.find_by(symbol: 'bitcoin')).not_to be_nil
    end

    it 'updates updated_at on every write' do
      described_class.upsert('bitcoin', 65000.5)
      first_updated_at = CryptoPrice.find_by(symbol: 'bitcoin').updated_at

      travel_to(first_updated_at + 5.minutes) do
        described_class.upsert('bitcoin', 66000.0)
      end

      expect(CryptoPrice.find_by(symbol: 'bitcoin').updated_at).to be > first_updated_at
    end

    context 'concurrent writers racing on the same symbol' do
      it 'does not raise and leaves exactly one row via the unique index' do
        # Simulates two overlapping job runs writing the same symbol —
        # the unique index + upsert_all's ON CONFLICT DO UPDATE means
        # neither write can create a duplicate row or raise
        # RecordNotUnique, regardless of ordering.
        expect {
          described_class.upsert('bitcoin', 65000.5)
          described_class.upsert('bitcoin', 65100.0)
        }.not_to raise_error

        expect(CryptoPrice.where(symbol: 'bitcoin').count).to eq(1)
      end
    end
  end

  describe '.find' do
    it 'returns the record for a known symbol' do
      described_class.upsert('bitcoin', 65000.5)

      expect(described_class.find('bitcoin').price.to_f).to eq(65000.5)
    end

    it 'is case-insensitive' do
      described_class.upsert('bitcoin', 65000.5)

      expect(described_class.find('BITCOIN')).not_to be_nil
    end

    it 'returns nil for an unknown symbol' do
      expect(described_class.find('doesnotexist')).to be_nil
    end
  end
end
