# 3. Imports run as background jobs, with the CSV carried in the job

## Status

Accepted (Phase 2).

## Context

A statement CSV can have thousands of rows. Parsing, fingerprinting,
categorizing, and inserting them takes long enough that doing it inside
the upload request would tie up the request and risk a timeout. The user
should see the import progress and result on the page, not a spinner that
either finishes or dies.

## Decision

Uploading a file creates an `Import` record with status `pending`, then
enqueues `Tally.Finance.ImportWorker` on the `:imports` Oban queue. The
CSV content is stored in the job's args. The worker runs
`Finance.run_import/4`, which writes the transactions and the import's
final status in one `Ecto.Multi`. It then broadcasts
`{:import_completed, import}` on the account's PubSub topic, so the
dashboard updates without a reload.

The CSV lives in the job args rather than in a file store. A statement is
a few hundred kilobytes at most, and it's needed only until the job runs.
Keeping it in the job avoids adding object storage to the deployment.

## Alternatives considered

- **Run the import in the upload request.** Simplest, but it blocks the
  request for the length of the import and gives no progress.
- **Store the file on disk or in object storage and pass a path.** The
  right choice for large uploads. It adds a storage dependency and a
  cleanup job that this app doesn't need at statement sizes.
- **Task.Supervisor instead of Oban.** No persistence: a restart mid-import
  loses the work with no record. Oban keeps the job in Postgres and retries
  it (up to three attempts).

## Consequences

- An import survives a restart, and retries are automatic.
- Job args are stored in Postgres, so very large uploads would bloat that
  table. The 5 MB upload limit in `AccountLive.Show` keeps this in bounds.
- Failures are visible: a bad file marks the import failed with a reason,
  and the dashboard shows it.
