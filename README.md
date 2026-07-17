# Crypto Price API

A Rails API-only app that fetches cryptocurrency prices from CoinGecko,
persists them, and serves them through a Redis-backed cache with a database
fallback.

## Requirements covered

This implementation satisfies the assignment by:

- Exposing `GET /prices/:symbol` to return the cached price for a given symbol.
- Running a background job every minute to fetch fresh prices and store them.
- Continuing to serve the last known price if CoinGecko is unavailable or returns an error.
- Keeping the default currency in the database and using it for the public API response.
- Including tests for job logic, fallback behavior, caching, and persistence.

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

Write Path
```
Sidekiq Scheduler
        │
        ▼
FetchCryptoPricesJob
        │
        ▼
CoingeckoClient
        │
        ▼
PriceRepository
        │
   Database
        │
        ▼
 PriceCache

```

Read path

```
GET /prices/:symbol
        │
        ▼
PricesController
        │
        ▼
PriceStore
   │           │
   ▼           ▼
Cache      Database
               │
               ▼
        Refresh Cache
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
app/controllers/prices_controller.rb   # validates the requested symbol and delegates to PriceStore
config/initializers/sidekiq_cron.rb    # schedules the job every minute
db/migrate/..._create_crypto_prices.rb # unique index on symbol/currency
```
Redis entries expire after 2 minutes, while the refresh job runs every minute.

## Installation guide

### Prerequisites

- Ruby 3.2.2
- Rails 6.1.7.10
- Bundler
- Redis (required for Rails cache and Sidekiq)

On macOS (Homebrew):

```bash
brew install redis
```

Verify the installation:

```bash
redis-server --version
redis-cli --version
```

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

### Start Redis

Start Redis as a background service:

```bash
brew services start redis
```

Or run it manually in a terminal:

```bash
redis-server
```

Verify Redis is running:

```bash
redis-cli ping
```

Expected output:

```text
PONG
```

### Clone the repository

```bash
git clone <repository-url>
cd crypto_price_api
bundle install
bundle exec rails db:create
bundle exec rails db:migrate
```

### Configure environment variables

```bash
export COINGECKO_API_KEY=your-key-here
export REDIS_URL=redis://localhost:6379/1
export DEFAULT_CURRENCY=usd
```

### Database setup

```bash
bundle exec rails db:create db:migrate
```

If this is your first time running the app locally, also prepare the test schema:

```bash
bundle exec rails db:prepare RAILS_ENV=test
```

## Project flow

1. A request hits `GET /prices/:symbol`.
2. The controller validates the symbol and calls the price store layer.
3. The app checks the Redis cache first, then falls back to the database if needed.
4. A background job runs every minute, fetches prices from CoinGecko in bulk, stores them in the database, and refreshes the cache.
5. If CoinGecko fails, the app continues serving the last stored price for that symbol.

## Supported cryptocurrencies

The supported coin list is kept in a YAML configuration file so it can be changed without touching the job logic.

Example configuration:

```yaml
# config/cryptocurrencies.yml
default:
  supported:
    - bitcoin
    - ethereum
    - solana
```

## Run the application

Open three terminals:

Terminal 1

```bash
redis-server
```

(or use `brew services start redis`)

Terminal 2

```bash
bundle exec rails server
```

Terminal 3

```bash
bundle exec sidekiq
```

The supported symbols come from the configuration file at `config/cryptocurrencies.yml`.
Add or remove entries there to change which coins the job refreshes.

## Verify the setup

Confirm Redis:

```bash
redis-cli ping
```

Expected:

```text
PONG
```

Confirm Sidekiq is connected:

```bash
bundle exec sidekiq
```

You should see Sidekiq start without Redis connection errors.

Confirm Rails:

```bash
curl http://localhost:3000/prices/bitcoin
```

Before the first job run you should receive a "not found" response.

After running the job, the endpoint should return the latest cached price.

## Run the job manually from the console

```bash
bundle exec rails console
```

```ruby
FetchCryptoPricesJob.perform_now(["bitcoin"])
```

You can also run it from the terminal without opening the console:

```bash
bundle exec rails runner 'FetchCryptoPricesJob.perform_now(["bitcoin"])'
```

## Insert data and test it

```bash
bundle exec rails console
```

```ruby
PriceStore.write(
  "bitcoin",
  50000.0,
  market_cap: 1_234_567_890.5,
  volume_24h: 98_765_432.1,
  price_change_24h: -1.25,
  provider_updated_at: Time.zone.now
)

PriceStore.read("bitcoin")
```

You can also insert a row directly with Active Record:

```ruby
CryptoPrice.create!(
  symbol: "bitcoin",
  price: 50000.0,
  market_cap: 1_234_567_890.5,
  volume_24h: 98_765_432.1,
  price_change_24h: -1.25,
  provider_updated_at: Time.zone.now
)
```

Then test it through the API:

```bash
curl http://localhost:3000/prices/bitcoin
```

The response will include the additional fields when they are present:

```json
{
  "symbol": "bitcoin",
  "currency": "usd",
  "price": 50000.0,
  "market_cap": 1234567890.5,
  "volume_24h": 98765432.1,
  "price_change_24h": -1.25,
  "updated_at": "2026-07-17T08:11:24Z"
}
```

## API example run

Example request:

```bash
curl http://localhost:3000/prices/bitcoin
```

Expected behavior:

- Before the first successful job run, the API returns a not-found response.
- After the job runs successfully, the API returns a payload similar to:

```json
{"symbol":"bitcoin","currency":"usd","price":65123.45,"updated_at":"2026-07-17T08:11:24Z"}
```

## Running the Test Suite

Prepare the test database (only required once or after adding new migrations):

```bash
bundle exec rails db:test:prepare
```

Run the complete test suite:

```bash
bundle exec rspec
```

### Test Coverage

The test suite contains **61 examples** covering the application's critical functionality:

- **spec/clients/coingecko_client_spec.rb**
  - Batched price fetching
  - API timeout handling
  - Non-2xx HTTP responses
  - Malformed JSON responses
  - Partial and missing symbol handling

- **spec/models/crypto_price_spec.rb**
  - Model validations
  - Symbol uniqueness
  - Symbol normalization

- **spec/services/price_repository_spec.rb**
  - Upsert semantics
  - Concurrent writer race condition handling

- **spec/services/price_cache_spec.rb**
  - Cache read/write round-trip
  - Cache overwrite behavior
  - TTL expiration

- **spec/services/price_store_spec.rb**
  - Database → Cache → Read pipeline
  - Cache miss fallback to the database
  - Cache refresh after persistence

- **spec/jobs/fetch_crypto_prices_job_spec.rb**
  - Batched price refresh
  - Symbol validation
  - Missing price fallback
  - Batch failure fallback
  - Partial batch failure isolation (one failing symbol does not block others)

- **spec/requests/prices_spec.rb**
  - End-to-end API request flow
  - Cached price retrieval
  - Database fallback on cache miss
  - Invalid symbol returns **422 Unprocessable Entity**
  - Consistent JSON response structure

The test suite validates the core business requirements, including caching behavior, persistence, background job execution, API integration, graceful degradation when the external provider is unavailable, and end-to-end request handling.

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
- If you want to inspect job behaviour in detail, run the console command above
  and check the Rails logs for any exception messages.
- If `bundle exec sidekiq` fails with `Redis::CannotConnectError`, verify Redis is installed and running:

```bash
redis-cli ping
```

If Redis is not running:

```bash
brew services start redis
```
