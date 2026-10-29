# 4. Recategorizing existing transactions batches updates by outcome, not by row

## Status

Accepted (recategorization feature).

## Context

A category rule only ever applied at import time — add a "Netflix"
rule today, and it does nothing for the "Netflix" transactions
already sitting in the database from last month. Fixing that means
re-running `CategoryRule.match/2` (the same function `Importer` uses)
against every transaction a user has, across every account, and
writing back whichever ones actually changed. A personal finance
history can run to several thousand rows; the question was how many
individual writes that turns into.

## Decision

`Finance.recategorize_transactions/1` loads every transaction's id,
`normalized_merchant`, and current `category` (three small columns,
not full rows) for the user across all their accounts, computes each
one's new category in Elixir, and discards any row whose category
didn't change. What's left is grouped by its *new* category value,
and each group becomes one `Repo.update_all/2` —
`WHERE id IN (...)`, one `UPDATE` per distinct resulting category
rather than one per transaction. A user whose history collapses onto
a handful of categories (which is the common case — most of anyone's
spending is a dozen or so recurring categories) gets a handful of
`UPDATE`s, not thousands.

## Alternatives considered

- **One `Repo.update_all/2` call per transaction.** Simplest to write,
  but turns a history of thousands of transactions into thousands of
  round trips for what's usually a result with far less variety than
  that — most transactions land on one of a small number of
  categories.
- **Build the whole computation as a single SQL statement** (a `CASE`
  expression per rule, or a join against rules). Would avoid pulling
  rows into Elixir at all, but `CategoryRule.match/2`'s "first rule
  whose `match_text` is a substring, in list order" semantics don't
  translate cleanly into a `CASE`/`WHEN` the database can evaluate —
  and duplicating that logic in SQL risks it drifting from what
  `Importer` actually does at import time, the exact thing sharing
  `CategoryRule.match/2` was meant to prevent.
- **Skip the no-op filter and just update every row.** Simpler code,
  but writes (and bumps `updated_at` on) every transaction regardless
  of whether anything actually changed — including the common case of
  running this with no new rules at all.

## Consequences

- The number of `UPDATE` statements scales with how many distinct
  categories actually changed, not with how many transactions did —
  the two are very different numbers in practice.
- Loading `{id, normalized_merchant, category}` for every transaction
  up front means the whole operation isn't incremental or resumable;
  it's one pass, computed in memory, then written. Fine at the scale
  this app targets (one person's or small team's history), and
  exactly the same scale assumption the rest of this app's design
  already makes.
- `CategoryRule.match/2` being the one place this match happens means
  a future change to matching rules (e.g. the "rule precedence"
  item in the README) only has to be made once to affect both new
  imports and a re-run of history the same way.
