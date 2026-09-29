defmodule Tally.Finance.Import do
  @moduledoc """
  Tracks one CSV upload's processing lifecycle and outcome: how many
  rows it had, how many actually landed, how many were skipped
  (duplicates) or errored (unparseable), and exactly which lines and
  why, via `error_details`. This schema is just the record of what
  happened; the import pipeline that actually parses and processes a
  CSV is a separate module.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:pending, :processing, :completed, :failed]

  @type t :: %__MODULE__{}

  schema "imports" do
    field :filename, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :rows_total, :integer, default: 0
    field :rows_imported, :integer, default: 0
    field :rows_skipped, :integer, default: 0
    field :rows_errored, :integer, default: 0
    field :error_details, {:array, :map}, default: []

    belongs_to :account, Tally.Finance.Account

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(import, attrs) do
    import
    |> cast(attrs, [:filename])
    |> validate_required([:filename])
  end

  @doc false
  def status_changeset(import, attrs) do
    cast(import, attrs, [
      :status,
      :rows_total,
      :rows_imported,
      :rows_skipped,
      :rows_errored,
      :error_details
    ])
  end
end
