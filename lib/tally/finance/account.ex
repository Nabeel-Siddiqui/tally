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

  alias Tally.Money

  @types [:checking, :credit_card]

  @type t :: %__MODULE__{}

  schema "accounts" do
    field :name, :string
    field :type, Ecto.Enum, values: @types
    field :opening_balance_cents, :integer, default: 0
    # Dollar-string form input ("1500.00", "-200.00") — never cast or
    # stored directly; put_opening_balance_cents/1 is what turns it
    # into opening_balance_cents, the same way Importer turns a CSV
    # row's amount string into cents (see Tally.Money).
    field :opening_balance, :string, virtual: true

    belongs_to :user, Tally.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(account, attrs) do
    account
    |> cast(attrs, [:name, :type, :opening_balance])
    |> validate_required([:name, :type])
    |> validate_length(:name, min: 1, max: 100)
    |> put_opening_balance_cents()
  end

  # A blank opening balance (the common case — most accounts start
  # fresh) defaults to 0, same as if the field didn't exist at all.
  defp put_opening_balance_cents(changeset) do
    case get_change(changeset, :opening_balance) do
      nil ->
        changeset

      "" ->
        put_change(changeset, :opening_balance_cents, 0)

      value ->
        case Money.parse_cents(value) do
          {:ok, cents} ->
            put_change(changeset, :opening_balance_cents, cents)

          :error ->
            add_error(changeset, :opening_balance, "must be a decimal like 1500.00 or -200.00")
        end
    end
  end
end
