# Development

## Setup

First things first, you'll need to fork and clone the repository to your local machine.

`git clone https://github.com/ecosyste-ms/repos.git`

The project uses ruby on rails which have a number of system dependencies you'll need to install.

- [ruby](https://www.ruby-lang.org/en/documentation/installation/)
- [postgresql 14](https://www.postgresql.org/download/)
- [redis 6+](https://redis.io/download/)
- [node.js 16+](https://nodejs.org/en/download/)

You will then need to set some configuration environment variables. Copy `env.example` to `.env.development` and customise the values to suit your local setup.

Once you've got all of those installed, from the root directory of the project run the following commands:

```
bin/setup
bin/dev
```

You can then load up [http://localhost:3000](http://localhost:3000) to access the service.

### Docker

Alternatively you can use the existing docker configuration files to run the app in a container.

Run this command from the root directory of the project to start the service.

`docker-compose up --build`

You can then load up [http://localhost:3000](http://localhost:3000) to access the service.

For access the rails console use the following command:

`docker-compose exec app rails console`

## Importing data

To set up an initial set of repository hosts:

`rake db:seed`

Then, you can run an sync to import some repositories:

`rake repositories:sync_recently_active`

## Tests

The applications tests can be found in [test](test) and use the testing framework [minitest](https://github.com/minitest/minitest).

You can run all the tests with:

`rails test`

## Rake tasks

The applications rake tasks can be found in [lib/tasks](lib/tasks).

You can list all of the available rake tasks with the following command:

`rake -T`

## Background tasks

Background tasks are handled by [sidekiq](https://github.com/mperham/sidekiq), the workers live in [app/sidekiq](app/sidekiq/).

Sidekiq is automatically run by `bin/dev`, but if you need to run it manually, run the following command:

`bundle exec sidekiq`

You can also view the status of the workers and their queues from the web interface http://localhost:3000/sidekiq


## Adding an host type

TODO

## Deployment

A container-based deployment is highly recommended, we use [dokku.com](https://dokku.com/).

Usage maintenance requires `REPOSITORY_USAGE_WRITES_ENABLED=true` and `REPOSITORY_USAGE_GENERATION=1`. Keep the generation fixed and writes enabled throughout recovery; pause the usage consumer to pause work without losing parse notifications. Run one instance of the dedicated `usage` process and use `REPOSITORY_USAGE_REPOSITORY_IDS` as a comma-separated allowlist for a pilot. Leave `REPOSITORY_USAGE_READ_GENERATION` unset while rebuilding; the API continues serving its old counts. Measure database I/O and queue age before widening the pilot.

With the allowlist removed, `bundle exec rails runner 'RepositoryUsage.crawl'` starts or resumes a single pass. Set `REPOSITORY_USAGE_BACKFILL_INTERVAL` explicitly to a non-negative delay in seconds, chosen from the pilot; there is no default. Lock waits and serialization failures retry the same batch through Sidekiq. Query timeouts, read-limit and contribution errors retain IDs for manual repair. Check `bundle exec rails runner 'pp RepositoryUsageBackfillWorker.status'`. Retry pending repositories with `RepositoryUsageBackfillWorker.retry_repository(id)`, which accepts `max_manifests`, `max_packages` and `statement_timeout` overrides. Status covers the captured ID range and pending repairs; also inspect usage jobs in Sidekiq's queue, retries and dead set before switching reads. Set `REPOSITORY_USAGE_READ_GENERATION=1` only when status reports `ready: true`. Changed parses maintain counts without another sweep. Repository destruction reverses contributions even when maintenance is paused; bulk SQL deletion bypasses that accounting.

## Alternative service domains

This service uses a number of other ecosyste.ms services, you can use alternative domains for these services by setting the following environment variables:

- PARSER_DOMAIN (default: https://parser.ecosyste.ms)
- ARCHIVES_DOMAIN (default: https://archives.ecosyste.ms)
- TIMELINE_DOMAIN (default: https://timeline.ecosyste.ms)
- COMMITS_DOMAIN (default: https://commits.ecosyste.ms)
- PACKAGES_DOMAIN (default: https://packages.ecosyste.ms)
