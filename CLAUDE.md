# Tally — conventions

Personal finance tracker. Portfolio-quality Elixir/Phoenix app; hold every
change to these rules. Keep it well-designed and finished — add complexity
only where this app actually needs it, not speculatively.

## Architecture

- **Business logic lives in contexts** (`Tally.Accounts`, `Tally.Finance`,
  ...). Contexts are the only modules that touch `Repo`.
- **The web layer (controllers, LiveViews, channels) never calls `Repo`
  directly** and never builds `Ecto.Query`s itself — it calls context
  functions.
- Oban workers call context functions too; they don't reach into `Repo`
  directly.

## Money

- **Money is always integer cents, never floats.** A float can't represent
  most currency amounts exactly (`0.1 + 0.2 != 0.3` in IEEE 754), and those
  small errors compound across thousands of transactions. Every
  `amount_cents` field is a plain integer; formatting as dollars-and-cents
  for display happens only at the presentation boundary, never in storage
  or in arithmetic.

## Function contracts

- Every public context function has `@doc` and `@spec`.
- Functions that can fail return `{:ok, result}` or `{:error, reason}` —
  never raise for expected failure modes (validation errors, not-found).
  Reserve `!`-suffixed functions for the conventional Phoenix
  "raise if truly not there" cases, matching what `phx.gen` produces.

## Testing

- Every feature ships with tests alongside it in the same phase/commit —
  not "add tests later."
- Prefer testing context functions directly over testing through LiveView
  where the logic under test isn't actually about the UI.

## Style

- Run `mix format` before committing.
- `mix credo --strict` and `mix dialyzer` must be clean before a phase is
  considered done.
