# How repositories stay up to date

repos.ecosyste.ms tracks repositories across GitHub, GitLab, Gitea, Bitbucket, and other hosts. Keeping them current involves crawling for new repositories, polling for recent changes, importing events from GHArchive, accepting pings from sibling services, and running periodic sweeps for anything that fell behind.

This is all best effort. repos.ecosyste.ms is a free, open source service and there are no guarantees about how fresh any given repository's data will be. The system prioritises recently active repositories and eventually catches up on the rest, but delays happen.

All scheduling is defined in [`app.json`](../app.json) as Heroku-style cron entries. All cron tasks use [`CronLock`](../lib/cron_lock.rb) (a Redis NX SET with TTL) to prevent overlapping executions. Sidekiq processes background jobs across several queues (critical, default, ping, extra, dependencies, tags).

## Discovering new repositories

Every 5 minutes, the [`repositories:crawl`](../lib/tasks/repositories.rake#L51) task calls [`Host#crawl_repositories_async`](../app/models/host.rb#L196) for each host. Each host type paginates through its API differently:

- **GitHub** queries timeline.ecosyste.ms's `/api/v1/events/repository_names`, which reflects the GitHub public events firehose. It paginates backward through event IDs to find recently active repository names.
- **GitLab** paginates through `/api/v4/projects?per_page=100&order_by=id`, storing the last page position in Redis for resumption.
- **Gitea** paginates through `/api/v1/repos/search?sort=id`, also storing progress in Redis.
- **Bitbucket** follows `next` link-based pagination from `/2.0/repositories?pagelen=100`, storing the continuation URL in Redis.

Any repository found during crawling that isn't already tracked gets created via [`Host#sync_repository`](../app/models/host.rb#L82).

## Polling for recently changed repositories

Every 15 minutes, [`repositories:sync_recently_active`](../lib/tasks/repositories.rake#L13) asks each host for repositories that changed in the last 15 minutes via [`Host#sync_recently_changed_repos_async`](../app/models/host.rb#L146).

Each host type implements [`recently_changed_repo_names`](../app/models/hosts/base.rb#L114) differently:

- **GitHub** ([`Hosts::Github#recently_changed_repo_names`](../app/models/hosts/github.rb#L403)) queries timeline.ecosyste.ms's `/api/v1/events/repository_names` endpoint, paging backward through events until it reaches the target time. This captures any repository that had a push, release, issue, PR, or other public event.
- **GitLab** ([`Hosts::Gitlab#recently_changed_repo_names`](../app/models/hosts/gitlab.rb#L222)) paginates projects sorted by `updated_at` descending, stopping when it reaches repos older than the target time.
- **Gitea** ([`Hosts::Gitea#recently_changed_repo_names`](../app/models/hosts/gitea.rb#L34)) does the same with its search API sorted by `updated`.

Up to 1000 repository names per host are queued for sync.

## GHArchive import

Every hour, [`gharchive:import_recent`](../app/models/host.rb) runs the [`GharchiveImporter`](../app/services/gharchive_importer.rb) which downloads and processes the GHArchive hourly data dump (with a 2-hour delay to allow for data availability).

The importer:

1. Downloads the gzipped JSONL file from `data.gharchive.org/{date}-{hour}.json.gz`
2. Filters for `PushEvent` and `ReleaseEvent` entries only
3. Groups events by repository name
4. For repos with a `ReleaseEvent`: if the repo is already tracked, queues a [`DownloadTagsWorker`](../app/sidekiq/download_tags_worker.rb) to fetch new tags. If not tracked, queues a [`PingWorker`](../app/sidekiq/ping_worker.rb) to create it.
5. For all repos with any event: queues a `PingWorker` to trigger a sync

Jobs are enqueued in batches of 1000. The [`Import`](../app/models/import.rb) model tracks which hours have been imported to avoid reprocessing.

## Tags and releases

Tags and releases are synced through several paths:

- **During extra details sync.** When a repository's `files_changed` flag is set (because `pushed_at` changed), [`sync_extra_details`](../app/models/repository.rb#L276) calls [`download_tags`](../app/models/repository.rb#L299), which fetches tags from the host API and then releases if any tags exist.
- **Via GHArchive.** Repositories with `ReleaseEvent` entries get their tags downloaded directly.
- **Via timeline.** Every 20 minutes, [`repositories:download_tags`](../lib/tasks/repositories.rake#L36) calls [`Hosts::Github#sync_repos_with_tags`](../app/models/hosts/github.rb#L425), which queries timeline.ecosyste.ms for recent `ReleaseEvent` entries and downloads tags for the affected repos.
- **Bulk catch-up.** [`Repository.download_tags_async`](../app/models/repository.rb#L71) queues up to 5000 non-fork repos ordered by `tags_last_synced_at` ascending, skipping if the tags queue already has over 5000 jobs.

For GitHub, tags are fetched via GraphQL ([`fetch_tags_graphql`](../app/models/hosts/github.rb#L259)) with pagination, 100 per page, ordered by commit date descending. Only new tags (not already in the database) are inserted.

## Inbound pings

Sibling ecosyste.ms services and external callers can trigger syncs via ping endpoints:

**Repository ping** -- [`GET /api/v1/hosts/:host_id/repositories/:id/ping`](../app/controllers/api/v1/repositories_controller.rb#L117)

Queues a [`PingWorker`](../app/sidekiq/ping_worker.rb#L1) which checks if the repo was synced in the last week. If so, it schedules a deferred re-sync 1 day later. Otherwise it syncs immediately and also queues [`sync_extra_details_async`](../app/models/repository.rb#L272) if the repo is a non-fork with changed files.

**Owner ping** -- [`GET /api/v1/hosts/:host_id/owners/:id/ping`](../app/controllers/api/v1/owners_controller.rb#L61)

Queues a `PingOwnerWorker` which syncs the owner record and their repositories.

**Package usage ping** -- [`GET /api/v1/usage/:ecosystem/:name/ping`](../app/controllers/api/v1/usage_controller.rb#L42)

Syncs package usage metadata from packages.ecosyste.ms for the given ecosystem/package combination.

## Outbound pings

When a repository is synced and any attribute has changed, repos pings packages.ecosyste.ms via [`ping_packages_async`](../app/models/repository.rb#L472). This queues a [`PingPackagesWorker`](../app/sidekiq/ping_packages_worker.rb) (with a 1-day uniqueness lock) that sends:

```
GET {PACKAGES_DOMAIN}/api/v1/packages/ping?repository_url={html_url}
```

This tells the packages service to re-sync all packages associated with that repository. The ping is triggered from two places:

- [`Host#sync_repository`](../app/models/host.rb#L123) -- when creating or updating a repo via the host API
- [`HostBase#update_from_host`](../app/models/hosts/base.rb#L195) -- when refreshing an existing repo's data

## Extra details

When a repository's files have changed (the `files_changed` flag is set because `pushed_at` moved), [`sync_extra_details`](../app/models/repository.rb#L276) runs the following:

1. **Parse dependencies** via [`parse_dependencies`](../app/models/repository.rb#L174) -- submits the repo's archive to parser.ecosyste.ms, which returns manifest files and their dependencies. If the parser job is still running, retries in 10 minutes. On completion, records manifests and dependencies, then updates [`RepositoryUsage`](../app/models/repository_usage.rb) records.
2. **Update metadata files** via [`update_metadata_files`](../app/models/repository.rb#L377) -- fetches the file list from archives.ecosyste.ms and looks for README, CHANGELOG, LICENSE, FUNDING, SECURITY, CITATION, and other standard files. Parses FUNDING.yaml/json for funding links.
3. **Download tags** via [`download_tags`](../app/models/repository.rb#L299).
4. **Sync scorecard** via `sync_scorecard_async` -- fetches the OpenSSF Scorecard from api.scorecard.dev.

The [`repositories:sync_extra_details`](../lib/tasks/repositories.rake#L22) cron task runs every 5 minutes (though the task body is currently commented out -- extra details are triggered reactively when `files_changed` is set during sync).

Dependency parsing has its own cron entry: [`repositories:parse_missing_dependencies`](../lib/tasks/repositories.rake#L29) runs every 15 minutes to retry pending parser jobs and queue non-fork repos that haven't been parsed yet, up to 2000 at a time, skipping if the dependencies queue exceeds 2000 jobs.

## Catch-up sweeps

Every 10 minutes, [`repositories:sync_least_recent`](../lib/tasks/repositories.rake#L4) queues the 2000 repositories with the oldest `last_synced_at` values, skipping if the default queue already has 10,000+ jobs.

## Sync throttling

- [`Repository#sync`](../app/models/repository.rb#L136) skips if synced in the last week (unless forced), scheduling a deferred re-sync 1 day after the last sync.
- [`PingWorker`](../app/sidekiq/ping_worker.rb#L10) applies the same 1-week freshness check.
- [`Repository.parse_dependencies_async`](../app/models/repository.rb#L61) checks the dependencies queue size and bails at 2000.
- [`Repository.download_tags_async`](../app/models/repository.rb#L71) checks the tags queue size and bails at 5000.
- Most workers use `sidekiq_options lock: :until_executed, lock_expiration: 1.day.to_i` to prevent duplicate jobs.

## Owner syncing

Every 10 minutes, [`hosts:sync_owners`](../lib/tasks/hosts.rake#L12) syncs the 2500 owners with the oldest `last_synced_at`.

[`Host#sync_owner`](../app/models/host.rb#L308) skips owners synced in the last week. Otherwise it:

1. Updates local counts (repositories_count, total_stars)
2. Fetches the owner record from the host API (via GraphQL for GitHub)
3. Creates or updates the Owner record with login, name, kind (user/org), avatar, bio, location, etc.
4. Calls `owner.sync_repositories` to sync their repos

## What happens during a repository sync

When [`Host#sync_repository`](../app/models/host.rb#L82) runs:

**For an existing repo:**
1. Call [`Repository#sync`](../app/models/repository.rb#L136), which checks freshness (1 week) and then calls `update_from_host`.

**For a new repo:**
1. Fetch repository data from the host API.
2. Validate essential fields (full_name, created_at, uuid).
3. Handle renames by tracking `previous_names`.
4. Set `files_changed = true` if `pushed_at` changed.
5. Save the record.
6. If anything changed: [`ping_packages_async`](../app/models/repository.rb#L472) to notify packages.ecosyste.ms.
7. If non-fork and files changed: [`sync_extra_details_async`](../app/models/repository.rb#L272) to parse dependencies, fetch metadata files, download tags, and fetch scorecard.
8. [`sync_owner`](../app/models/host.rb#L308) to ensure the owner record exists and is current.

## Housekeeping

| Schedule | Task |
|---|---|
| Daily midnight | [`hosts:check_github_tokens`](../lib/tasks/hosts.rake#L4) -- validates all stored GitHub API tokens |
| Daily 2am | [`hosts:check_status`](../lib/tasks/hosts.rake#L19) -- checks HTTP status and response time for each host |
| Daily 4am | [`repositories:fetch_dependencies_for_github_actions_tags`](../lib/tasks/repositories.rake#L67) -- special dependency parsing for GitHub Actions tags |
| Daily 6am | `sitemap:refresh_with_lock` -- regenerates the sitemap |
| Weekly (Sunday midnight) | [`repositories:clean_up_sidekiq_unique_jobs`](../lib/tasks/repositories.rake#L74) -- clears the unique jobs digest set |

## Reporting problems

If a repository is out of date or missing, open an issue at https://github.com/ecosyste-ms/repos/issues with:

- The host and repository full name (or URL on repos.ecosyste.ms)
- What you expected to see vs what's showing
- When the repository was last pushed to or had a release, if you know
- Whether the repository was recently renamed, transferred, or made private
