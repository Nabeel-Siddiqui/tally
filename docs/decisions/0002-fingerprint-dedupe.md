# 2. Duplicate transactions are rejected by a database index, not by application code

## Status

Accepted (Phase 1, wired up in Phase 2).

## Context

People re-upload overlapping statements: the same month exported twice,
or two exports whose date ranges overlap. Without a rule, every
re-uploaded transaction is inserted again and the balance doubles.

The question is where the rule lives. Application code can check "does
this already exist?" before inserting, but that check races with a
concurrent import of the same file, and it has to be remembered in every
code path that inserts a transaction.

## Decision

Each transaction gets a `fingerprint`: a SHA-256 of its date, amount in
cents, and trimmed, lowercased description. The fingerprint is computed by
the changeset (`Transaction.fingerprint/3`), so every insertion path gets
it the same way. A unique index on `(account_id, fingerprint)` makes the
database refuse a second copy.

Bulk imports use `Repo.insert_all/3` with `on_conflict: :nothing` and
`conflict_target: [:account_id, :fingerprint]`. Rows that already exist
are skipped without raising, and the import reports how many were skipped.

## Alternatives considered

- **Check-then-insert in Elixir.** Simple to read, but racy: two
  concurrent imports can both see "not present" and both insert. It also
  needs a query per row, or one query up front that every insert path
  must respect.
- **A natural key from the bank's own transaction ID.** Better when the
  bank provides one, but the CSV exports used here don't include an ID.
  The fingerprint works from the fields every export has.

## Consequences

- The guarantee holds regardless of which code path inserts a
  transaction, and under concurrent imports.
- Two genuinely separate transactions with the same date, amount, and
  description (two identical coffees on one day) collapse into one row.
  That's a real tradeoff. A bank export doesn't distinguish them, so
  Tally can't either without a bank-provided ID.
