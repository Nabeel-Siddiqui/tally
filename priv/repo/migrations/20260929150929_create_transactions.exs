defmodule Tally.Repo.Migrations.CreateTransactions do
  use Ecto.Migration

  def change do
    create table(:transactions) do
      add :posted_on, :date, null: false
      add :description, :string, null: false
      add :normalized_merchant, :string
      # Integer cents, always — never a float. See CLAUDE.md and
      # Tally.Finance.Transaction's moduledoc for why. Negative for
      # spending, positive for a credit/refund, matching the sign
      # convention a real bank statement uses.
      add :amount_cents, :integer, null: false
      add :category, :string
      # sha256(posted_on|amount_cents|normalized description), computed
      # by the changeset itself so every insertion path gets it the same
      # way. This is what re-uploading an overlapping statement checks
      # against.
      add :fingerprint, :string, null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    # The database, not just application code, guarantees a duplicate
    # row from an overlapping CSV re-upload can never be inserted twice.
    create unique_index(:transactions, [:account_id, :fingerprint])

    # Matches Finance.list_transactions/1's actual query today (scoped to
    # one account, ordered by posted_on).
    create index(:transactions, [:account_id, :posted_on])
  end
end
