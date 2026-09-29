defmodule Tally.Repo.Migrations.CreateImports do
  use Ecto.Migration

  def change do
    create table(:imports) do
      add :filename, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :rows_total, :integer, null: false, default: 0
      add :rows_imported, :integer, null: false, default: 0
      add :rows_skipped, :integer, null: false, default: 0
      add :rows_errored, :integer, null: false, default: 0
      # One entry per bad row: %{"line" => n, "reason" => "..."} — enough
      # to tell a user exactly which lines of their CSV didn't make it in
      # and why, without failing the whole import over a few bad rows.
      add :error_details, {:array, :map}, null: false, default: []
      add :account_id, references(:accounts, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:imports, [:account_id])
  end
end
