# 1. Money is stored as integer cents, never as floats

## Status

Accepted (Phase 1).

## Context

Every transaction has an amount, and the app sums them for balances,
category totals, and monthly trends. A float can't represent most
currency values exactly (`0.1 + 0.2` is `0.30000000000000004` in IEEE
754), and small errors compound across thousands of rows. A balance that
is off by a cent is a correctness bug, not a rounding quirk.

## Decision

`amount_cents` is a plain `integer` column in Postgres and in the schema.
Negative means spending, positive means a credit or refund, the same sign
convention a bank statement uses. Dollars-and-cents text is produced only
at the presentation boundary (`TallyWeb.Money.format/1`). Storage and
arithmetic never touch a float.

The CSV importer parses `"-4.50"` by splitting on the decimal point and
doing integer arithmetic on the parts. It does not call `String.to_float/1`.

## Alternatives considered

- **`:decimal` (Decimal library).** Exact, and the standard answer in
  many Elixir apps. It's heavier than this app needs: every sum and
  comparison goes through a struct, and the database column type has to be
  numeric with a fixed scale. Integer cents give the same exactness with
  plain arithmetic, and the scale is fixed by the convention, not by the
  column definition.
- **Float with rounding at display time.** This is the approach the rule
  is meant to rule out. Sums drift, and rounding at display hides the
  drift instead of preventing it.

## Consequences

- Every sum is exact, and the balance test in `finance_test.exs` checks
  exact integer results.
- Anyone reading the database sees `-450`, not `-4.5`, and has to know the
  convention. The moduledoc on `Tally.Finance.Transaction` documents it.
