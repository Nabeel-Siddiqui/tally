defmodule Tally.Repo.Migrations.CreateCategoryRules do
  use Ecto.Migration

  def change do
    create table(:category_rules) do
      add :match_text, :string, null: false
      add :category, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:category_rules, [:user_id])

    # A second "always categorize this merchant this way" for the same
    # match text should update the existing rule, not create a
    # competing duplicate.
    create unique_index(:category_rules, [:user_id, :match_text])
  end
end
