defmodule Tally.Finance.CategoryRule do
  @moduledoc """
  A user's standing instruction: any transaction whose merchant matches
  `match_text` should be filed under `category`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "category_rules" do
    field :match_text, :string
    field :category, :string

    belongs_to :user, Tally.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:match_text, :category])
    |> validate_required([:match_text, :category])
    |> update_change(:match_text, &String.trim/1)
    |> validate_length(:match_text, min: 1, max: 200)
    |> validate_length(:category, min: 1, max: 100)
    |> unique_constraint(:match_text, name: :category_rules_user_id_match_text_index)
  end

  @doc """
  The category of the first rule (in list order) whose `match_text`
  appears in `normalized_merchant`, case-insensitively — or `nil` if
  none match. The one place this match is actually performed, used
  both when a transaction is first imported
  (`Tally.Finance.Importer`) and when rules are reapplied to
  transactions that already exist (`Tally.Finance.recategorize_transactions/1`),
  so the two can never disagree about what a given merchant matches.
  """
  @spec match([t()], String.t()) :: String.t() | nil
  def match(category_rules, normalized_merchant) when is_binary(normalized_merchant) do
    downcased_merchant = String.downcase(normalized_merchant)

    Enum.find_value(category_rules, fn rule ->
      if String.contains?(downcased_merchant, String.downcase(rule.match_text)),
        do: rule.category
    end)
  end
end
