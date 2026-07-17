# Schedules FetchCryptoPricesJob to run every minute. Only loaded on the
# Sidekiq server process (not in web/console/test processes), matching the
# sidekiq-cron recommendation for avoiding duplicate schedule loads.
if Sidekiq.server?
  begin
    Sidekiq::Cron::Job.create(
      name: "Fetch crypto prices - every minute",
      cron: "* * * * *",
      class: "FetchCryptoPricesJob"
    )
  rescue Redis::CannotConnectError, RedisClient::CannotConnectError, Errno::ECONNREFUSED => e
    Rails.logger.warn("Skipping Sidekiq cron registration because Redis is unavailable: #{e.message}")
  end
end
