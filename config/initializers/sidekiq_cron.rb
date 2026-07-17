# Schedules FetchCryptoPricesJob to run every minute. Only loaded on the
# Sidekiq server process (not in web/console/test processes), matching the
# sidekiq-cron recommendation for avoiding duplicate schedule loads.
if Sidekiq.server?
  Sidekiq::Cron::Job.create(
    name: "Fetch crypto prices - every minute",
    cron: "* * * * *",
    class: "FetchCryptoPricesJob"
  )
end
