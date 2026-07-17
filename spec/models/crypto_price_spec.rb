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

  it 'enforces uniqueness on symbol' do
    described_class.create!(symbol: 'bitcoin', price: 65000.5)
    duplicate = described_class.new(symbol: 'bitcoin', price: 70000.0)

    expect(duplicate).not_to be_valid
  end

  it 'normalizes the symbol to lowercase before validation' do
    record = described_class.new(symbol: 'BITCOIN', price: 65000.5)
    record.valid?

    expect(record.symbol).to eq('bitcoin')
  end
end
