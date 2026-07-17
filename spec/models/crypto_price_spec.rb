require 'rails_helper'

RSpec.describe CryptoPrice, type: :model do
  it 'is valid with a symbol and a positive price' do
    record = described_class.new(symbol: 'bitcoin', price: 65000.5)
    expect(record).to be_valid
  end

  it 'requires a symbol' do
    record = described_class.new(symbol: nil, price: 65000.5)
    expect(record).not_to be_valid
  end

  it 'requires a positive price' do
    record = described_class.new(symbol: 'bitcoin', price: 0)
    expect(record).not_to be_valid

    record.price = -5
    expect(record).not_to be_valid
  end

  it 'enforces uniqueness on symbol and currency' do
    described_class.create!(symbol: 'bitcoin', currency: 'usd', price: 65000.5)
    duplicate = described_class.new(symbol: 'bitcoin', currency: 'usd', price: 70000.0)

    expect(duplicate).not_to be_valid
  end

  it 'allows the same symbol in a different currency' do
    described_class.create!(symbol: 'bitcoin', currency: 'usd', price: 65000.5)
    other_currency = described_class.new(symbol: 'bitcoin', currency: 'eur', price: 60000.0)

    expect(other_currency).to be_valid
  end

  it 'defaults currency to usd when not provided' do
    record = described_class.new(symbol: 'bitcoin', price: 65000.5)
    record.valid?

    expect(record.currency).to eq('usd')
  end

  it 'normalizes the symbol to lowercase before validation' do
    record = described_class.new(symbol: 'BITCOIN', price: 65000.5)
    record.valid?

    expect(record.symbol).to eq('bitcoin')
  end
end
