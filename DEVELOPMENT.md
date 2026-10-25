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

Usage maintenance is disabled unless `REPOSITORY_USAGE_WRITES_ENABLED=true`.
Set `REPOSITORY_USAGE_REPOSITORY_IDS` to a comma-separated allowlist of repository IDs for a pilot. An unset or empty allowlist enables all repositories when the write flag is on. The flag is checked both when enqueuing and when processing jobs. Disable it to stop subsequent usage writes, then let any running transaction finish.

Before enabling a pilot, establish both package counters from distinct repository memberships in `repository_usages` for every package it can add or remove. Existing counters may be stale even when they agree. Do this separately with bounded runner scripts or offline exports; do not run a global recount on production. Reconciliation rejects missing, unequal or underflowing counters, but cannot detect equal stale values. Repairing the baseline does not reconcile historical relationships; those still need a separate catch-up.

Start with a small allowlist and one consumer of the existing `usage` queue. Account for every worker process that consumes that queue when setting concurrency. Worker transactions cap manifest and package sets, use a 2-second statement timeout and a 250-millisecond lock timeout, and roll back on failure. These are per-statement limits, not a total job deadline. Inspect queue age, retries, database I/O and WAL through runner scripts and existing monitoring before widening the pilot. Oversized repositories remain unreconciled until handled separately; do not treat a read limit as an empty snapshot.

Successful repository parses enqueue after their observations commit. Jobs coalesce while waiting, and a parse during a running job can enqueue another refresh. Current manifests and lockfiles contribute one membership per package; tag-only observations do not. Requirement changes leave memberships untouched. During the pilot, manifests without a SHA compare dependency observations before replacing them. Repository destruction decrements memberships in the destroy transaction. Bulk SQL deletes bypass these callbacks and require separate counter repair.

## Alternative service domains

This service uses a number of other ecosyste.ms services, you can use alternative domains for these services by setting the following environment variables:

- PARSER_DOMAIN (default: https://parser.ecosyste.ms)
- ARCHIVES_DOMAIN (default: https://archives.ecosyste.ms)
- TIMELINE_DOMAIN (default: https://timeline.ecosyste.ms)
- COMMITS_DOMAIN (default: https://commits.ecosyste.ms)
- PACKAGES_DOMAIN (default: https://packages.ecosyste.ms)
