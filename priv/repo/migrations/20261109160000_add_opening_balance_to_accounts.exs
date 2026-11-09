defmodule Tally.Repo.Migrations.AddOpeningBalanceToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :opening_balance_cents, :integer, null: false, default: 0
    end
  end
end
