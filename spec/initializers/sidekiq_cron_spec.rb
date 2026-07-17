require 'rails_helper'

RSpec.describe 'sidekiq cron initializer' do
  it 'does not raise when Redis is unavailable during cron registration' do
    allow(Sidekiq).to receive(:server?).and_return(true)
    allow(Sidekiq::Cron::Job).to receive(:create).and_raise(Redis::CannotConnectError, 'boom')
    allow(Rails.logger).to receive(:warn)

    expect { load Rails.root.join('config/initializers/sidekiq_cron.rb') }.not_to raise_error
    expect(Rails.logger).to have_received(:warn).with(/Skipping Sidekiq cron registration/)
  end
end
