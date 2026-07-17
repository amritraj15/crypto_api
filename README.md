# Crypto Price API

A Rails API-only app that fetches cryptocurrency prices from CoinGecko,
persists them, and serves them with a fast cache in front — falling back to
the database, then to the last known DB value, when things fail upstream.

## Requirements covered

This implementation satisfies the original problem statement by:

- Exposing `GET /prices/:symbol` to return the cached cryptocurrency price
  for a given symbol and currency.
- Running a background job every minute to fetch fresh prices and store them.
- Continuing to serve the last known price if the external CoinGecko API is
  unavailable or returns an error.
- Storing currency-specific prices in the database and falling back to the
  last known value for that currency.
- Including unit tests for job logic, fallback behavior, and caching behavior.

## Installation guide

### Prerequisites

- Ruby 3.2.2
- Rails 6.1.7.10 (the Gemfile pins Rails to `~> 6.1.7`)
- Redis (required for Rails cache and Sidekiq)
- Bundler

### Install Ruby and Rails

If you use `rbenv`:

```bash
rbenv install 3.2.2
rbenv local 3.2.2
gem install bundler
```

If you use `rvm`:

```bash
rvm install 3.2.2
rvm use 3.2.2
gem install bundler
```

### Clone the repository

```bash
git clone <repository-url>
cd crypto_price_api
bundle install
```

### Configure environment variables

```bash
export COINGECKO_API_KEY=CG-u5ZvsvVpyous4vka8YZcQcAr
export REDIS_URL=redis://localhost:6379/1
```

### Database setup

```bash
bundle exec rails db:create db:migrate
```

If this is your first time running the app locally, also prepare the test
schema before running the spec suite:

```bash
bundle exec rails db:prepare RAILS_ENV=test
```

If you see an error such as `no such table: crypto_prices`, rerun the
migration commands above to create the missing table.

## Project flow

1. A request hits `GET /prices/:symbol?currency=usd`.
2. The controller validates symbol and currency, then calls the price store
   layer.
3. The app checks the in-memory/Redis cache first, then falls back to the
   database if the cache is empty or expired.
4. A background job runs every minute, fetches prices from CoinGecko in bulk
   per currency, stores them in the database, and refreshes the cache.
5. If CoinGecko fails, the app continues serving the last stored price for
   that symbol/currency combination.

## Supported cryptocurrencies and currencies

The app is designed to support multiple cryptocurrencies and currencies at
the same time. Prices are stored per symbol/currency pair so the same symbol
can be tracked in different fiat currencies.

The supported coin list is kept in a YAML configuration file so it can be
changed easily without touching the job logic.

Example configuration:

```yaml
# config/cryptocurrencies.yml
default:
  supported:
    - bitcoin
    - ethereum
    - solana
```

A simple provider abstraction exposes the list to the job:

```ruby
class CryptocurrencyProvider
  def self.supported
    Rails.application.config_for(:cryptocurrencies).fetch("supported", [])
  end
end
```

### Currency defaults

The public API remains `GET /prices/:symbol` and does not depend on a currency
query parameter. The internal data model still stores currency so future
enhancements can support multiple currencies without changing the API.

If no currency is provided by internal job or storage logic, the app defaults
to `usd`.

This keeps the implementation configurable today and makes it easy to replace
with a database-backed approach later, for example if you want an admin UI to
add or remove cryptocurrencies without changing the public API.

## Run the application

Set your CoinGecko API key as an environment variable (do **not** hardcode
it in source or commit it):

```bash
export COINGECKO_API_KEY=your-key-here
export REDIS_URL=redis://localhost:6379/1   # optional, this is the default
```

Start Redis, then in separate terminals:

```bash
bundle exec rails server              # API on http://localhost:3000
bundle exec sidekiq                   # runs FetchCryptoPricesJob every minute
```

The supported symbols come from the configuration file at
`config/cryptocurrencies.yml` and the `CryptocurrencyProvider` service.
Add or remove entries there to change which coins the job refreshes, or call
`FetchCryptoPricesJob.perform_now(["dogecoin"])` for an ad hoc symbol.

If you need a non-default currency, call the job with currency-aware items:

```ruby
FetchCryptoPricesJob.perform_now([
  { symbol: 'bitcoin', currency: 'usd' },
  { symbol: 'ethereum', currency: 'eur' }
])
```

The API route remains `GET /prices/:symbol`. The controller does not require
or parse a currency query parameter for reads; it always reads the default
currency internally.

## Run the job manually from the console

You can also trigger the price refresh directly without waiting for the scheduled job:

```bash
bundle exec rails console
```

Then run:

```ruby
FetchCryptoPricesJob.perform_now(["bitcoin"])
```

You can also run it from the terminal without opening the console:

```bash
bundle exec rails runner 'FetchCryptoPricesJob.perform_now(["bitcoin"])'
```

## Insert data into the database and test it

You can seed a price directly through the app service layer:

```bash
bundle exec rails console
```

```ruby
PriceStore.write("bitcoin", 50000.0)
PriceStore.read("bitcoin")
```

You can also insert a row directly with Active Record:

```ruby
CryptoPrice.create!(symbol: "bitcoin", price: 50000.0)
```

After inserting the record, test it through the API:

```bash
curl http://localhost:3000/prices/bitcoin
```

Or verify it from the Rails console:

```ruby
PriceStore.read("bitcoin")
```

## API example run

Start Redis:

```bash
redis-server
```

Start the API and background worker in separate terminals:

```bash
bundle exec rails server
bundle exec sidekiq
```

Example request:

```bash
curl http://localhost:3000/prices/bitcoin?currency=eur
```

Expected behavior:

- Before the first successful job run, the API returns:

```json
{"error":"no price cached yet for bitcoin eur"}
```

- After the job runs successfully, the API returns a payload similar to:

```json
{"symbol":"bitcoin","currency":"eur","price":65123.45,"updated_at":"2026-07-17T08:11:24Z"}
```

## Test case run

Run the test suite with:

```bash
bundle exec rails db:test:prepare   # only needed once, or after a new migration
bundle exec rspec
```

53 examples across:
- `spec/clients/coingecko_client_spec.rb` — batching, timeouts, non-2xx,
  malformed JSON, partial/missing symbols
- `spec/models/crypto_price_spec.rb` — validations, uniqueness, symbol
  normalization
- `spec/services/price_repository_spec.rb` — upsert semantics, including a
  concurrent-writer race test
- `spec/services/price_cache_spec.rb` — round-trip, overwrite, TTL expiry
- `spec/services/price_store_spec.rb` — the DB -> cache -> read pipeline,
  including the cache-miss-falls-back-to-DB path
- `spec/jobs/fetch_crypto_prices_job_spec.rb` — batching, symbol
  validation, fallback-on-missing-price, fallback-on-batch-failure,
  one-symbol-failure-doesn't-block-others
- `spec/requests/prices_spec.rb` — end-to-end, including invalid-symbol 422

WebMock stubs the CoinGecko HTTP call, so the suite never hits the real
network. `config.active_job.queue_adapter = :test` in
`config/environments/test.rb` runs jobs synchronously — no real
Sidekiq/Redis process is required to run the suite, though a real SQLite
test database is used (`db:test:prepare` sets it up from the migrations).

The test suite covers:

- Job logic
- Fallback behavior when the external API fails
- Caching behavior and persistence flow

## Architecture

```
CoinGecko
   |
   v
CoingeckoClient        (app/clients/coingecko_client.rb — ONLY file that knows the CoinGecko API shape)
   |
   v
Database (crypto_prices)   <- source of truth, survives restarts
   |
   v
Redis / Rails.cache         <- fast path, bounded TTL
   |
   v
Controller (GET /prices/:symbol)
```

```
app/clients/coingecko_client.rb        # CoinGecko API call only. Batches all
                                        # requested symbols into one request.
                                        # If the provider or response shape
                                        # changes, this is the only file that
                                        # needs to.
app/models/crypto_price.rb             # AR model — the source of truth
app/services/price_repository.rb       # all DB reads/writes go through here
app/services/price_cache.rb            # Rails.cache wrapper, bounded TTL
app/services/price_store.rb            # coordinates DB -> cache; the only
                                        # thing the job/controller talk to
app/services/symbol_validator.rb       # format-checks a symbol before it's
                                        # used in a DB query or API call
app/jobs/fetch_crypto_prices_job.rb    # every minute: fetch -> persist
app/controllers/prices_controller.rb   # thin — validates symbol+currency, then PriceStore.read
config/initializers/sidekiq_cron.rb    # schedules the job every minute
db/migrate/..._create_crypto_prices.rb # unique index on symbol/currency
```

### Why the database is the source of truth

The cache now has a TTL (`PriceCache::EXPIRES_IN`, 2 minutes — longer than
the job's 1-minute cadence so a single slow/missed run doesn't cause a wave
of DB reads, but short enough that a broken job doesn't leave stale data
serving forever). `PriceStore.read` tries the cache first and falls back to
the database on a miss, repopulating the cache so the next read doesn't need
to. `PriceStore.write` always persists to the DB first, then mirrors into
the cache — so a Redis restart or eviction never loses data, only some
read-latency until the cache warms back up.

### Why CoingeckoClient is separate from everything else

`CoingeckoClient#fetch_prices` takes symbols in and returns `{ symbol =>
price }` out, or raises `CoingeckoClient::Error`. It has zero knowledge of
the database, the cache, or Sidekiq. If CoinGecko changes their response
shape, or you swap providers entirely, this is the only file that changes —
`FetchCryptoPricesJob`, `PriceStore`, and the controller are all untouched.

### Concurrency: why `upsert_all` instead of `find_or_create_by`

`PriceRepository.upsert` uses `CryptoPrice.upsert_all` (a single atomic
`INSERT ... ON CONFLICT symbol DO UPDATE`) rather than a
read-then-write pattern. Two job runs can overlap — a slow run plus the next
minute's scheduled run — and both may write the same symbol. A
find-then-save has a race window where both processes could see "no row
yet" and both try to `INSERT`, which the unique index on `symbol` would
correctly reject but as a crash (`ActiveRecord::RecordNotUnique`) rather
than a clean update. Pushing the conflict resolution into the database
avoids that window entirely. `spec/services/price_repository_spec.rb` has a
test exercising two overlapping writes to confirm exactly one row survives
with no error.

### Symbol validation

`SymbolValidator` checks a simple format (`[a-z0-9-]`) before a symbol is
used anywhere — the controller rejects a malformed `:symbol` param with 422
before touching the cache or DB, and the job filters out anything invalid
from its symbol list before spending an API call on it.

### Batching

`FetchCryptoPricesJob` fetches all tracked symbols in **one** CoinGecko
request (`CoingeckoClient.new(symbols).fetch_prices`, using CoinGecko's
comma-separated `ids` parameter) rather than one request per symbol.

### Logging

Every failure path — a single symbol missing from the response, the whole
batch request failing, an unexpected exception while persisting — logs a
tagged, actionable message (`[FetchCryptoPricesJob] ...`) rather than
failing silently. The job also has a top-level rescue so an unhandled
exception doesn't just vanish from Sidekiq's normal job flow.

## What's out of scope

- Auth/rate limiting on the `/prices/:symbol` endpoint itself.
- Multi-currency (`vs_currencies` is hardcoded to `usd`).
- A real production Redis/Postgres deployment config — SQLite is used here
  to keep the assignment self-contained; swapping `config/database.yml` to
  Postgres would need no other code changes since all DB access goes
  through `PriceRepository`/`CryptoPrice`.

## Troubleshooting

- If the API returns `no price cached yet`, check that Redis is running and
  that the background job has executed at least once.
- If the job does not update prices, confirm that Sidekiq is running and that
  the CoinGecko API key is exported correctly.
- If you see a `422` response, make sure the symbol is lowercase and uses only
  letters, numbers, or hyphens (for example, `bitcoin` or `dogecoin`).
- If the app cannot connect to Redis, start it with `redis-server` and verify
  the `REDIS_URL` environment variable.
- If you want to inspect job behavior in detail, run the console command above
  and check the Rails logs for any exception messages.
