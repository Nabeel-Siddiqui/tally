defmodule Tally.Finance.Account do
  @moduledoc """
  A bank or credit card account a user tracks transactions for.

  Named `Finance.Account`, distinct from `Accounts.User` (the login
  identity) — a deliberate naming choice, not a collision. "Account" in
  this app means a financial account (checking, credit card) that a CSV
  statement belongs to, not a user's login.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @types [:checking, :credit_card]

  @type t :: %__MODULE__{}

  schema "accounts" do
    field :name, :string
    field :type, Ecto.Enum, values: @types

    belongs_to :user, Tally.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(account, attrs) do
    account
    |> cast(attrs, [:name, :type])
    |> validate_required([:name, :type])
    |> validate_length(:name, min: 1, max: 100)
  end
end
