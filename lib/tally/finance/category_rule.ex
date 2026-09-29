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
end
