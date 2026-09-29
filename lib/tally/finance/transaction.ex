defmodule Tally.Finance.Transaction do
  @moduledoc """
  A single posted transaction on an account, imported from a bank
  statement CSV.

  `amount_cents` is always an integer, never a float (see CLAUDE.md for
  why). Negative for spending, positive for a credit or refund, the same
  sign convention a real bank statement uses.

  `fingerprint` is what makes re-uploading an overlapping statement
  safe: a hash of the date, amount, and a normalized description,
  computed by this module's own changeset rather than left to each
  caller to remember, backed by a unique index on
  `(account_id, fingerprint)`. See `Tally.Finance.create_transaction/3`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "transactions" do
    field :posted_on, :date
    field :description, :string
    field :normalized_merchant, :string
    field :amount_cents, :integer
    field :category, :string
    field :fingerprint, :string

    belongs_to :account, Tally.Finance.Account

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [:posted_on, :description, :normalized_merchant, :amount_cents, :category])
    |> validate_required([:posted_on, :description, :amount_cents])
    |> validate_length(:description, min: 1, max: 500)
    |> put_fingerprint()
    # unique_constraint/3 with a list of fields attaches its error to the
    # *first* field by default — here that would be :account_id, which
    # reads strangely ("account has already been taken") for what's
    # actually a duplicate-transaction error. Naming the field and the
    # index explicitly attaches it to :fingerprint instead, where it
    # actually belongs.
    |> unique_constraint(:fingerprint, name: :transactions_account_id_fingerprint_index)
  end

  @doc false
  def category_changeset(transaction, category) do
    change(transaction, category: category)
  end

  defp put_fingerprint(changeset) do
    with posted_on when not is_nil(posted_on) <- get_field(changeset, :posted_on),
         amount_cents when not is_nil(amount_cents) <- get_field(changeset, :amount_cents),
         description when not is_nil(description) <- get_field(changeset, :description) do
      put_change(changeset, :fingerprint, fingerprint(posted_on, amount_cents, description))
    else
      _ -> changeset
    end
  end

  @doc """
  Computes the duplicate-detection fingerprint for a transaction: a
  hash of its date, amount, and a normalized (trimmed, lowercased)
  description. The same three inputs always produce the same
  fingerprint regardless of which import produced them — that's what
  lets a bulk insert with `on_conflict: :nothing` (Phase 2) recognize
  the same real-world transaction appearing twice across two
  overlapping CSV uploads.
  """
  @spec fingerprint(Date.t(), integer(), String.t()) :: String.t()
  def fingerprint(%Date{} = posted_on, amount_cents, description)
      when is_integer(amount_cents) and is_binary(description) do
    normalized_description = description |> String.trim() |> String.downcase()
    payload = "#{Date.to_iso8601(posted_on)}|#{amount_cents}|#{normalized_description}"

    :sha256
    |> :crypto.hash(payload)
    |> Base.encode16(case: :lower)
  end
end
