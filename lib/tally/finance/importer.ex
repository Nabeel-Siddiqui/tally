NimbleCSV.define(Tally.Finance.Importer.Parser, separator: ",", escape: "\"")

defmodule Tally.Finance.Importer do
  @moduledoc """
  Parses a bank statement CSV into transaction attributes ready for
  `Repo.insert_all/3`, plus per-row error details for anything that
  didn't parse. Pure — no `Repo` calls here — so it's fully testable
  with plain CSV strings. `Tally.Finance.run_import/4` is the only
  caller, and it owns actually writing the result to the database.

  Expects a header row naming `date`, `description`, and `amount`
  (case-insensitive, any column order; extra columns are ignored).
  `date` must be ISO 8601 (`YYYY-MM-DD`); `amount` must be a plain
  decimal string with exactly two decimal places, like `-4.50` or
  `1200.00` — this is deliberately one documented format rather than
  guessing across the many shapes real bank exports use, and it's never
  parsed as a float (see CLAUDE.md on money).
  """

  alias Tally.Finance.{CategoryRule, Transaction}
  alias Tally.Finance.Importer.Parser

  @required_columns ~w(date description amount)
  @amount_pattern ~r/^(-?)\$?([\d,]+)\.(\d{2})$/

  @type row_error :: %{row: pos_integer(), reason: String.t()}
  @type result :: %{
          transactions: [map()],
          rows_total: non_neg_integer(),
          rows_errored: non_neg_integer(),
          error_details: [row_error()]
        }

  @doc """
  Parses `csv_content` into transaction attribute maps (each with
  `fingerprint`, `normalized_merchant`, and `category` already filled
  in) plus error details for any row that didn't parse. `category_rules`
  should be the uploading user's rules — the first one whose
  `match_text` appears in a transaction's normalized merchant wins.
  """
  @spec process(String.t(), [CategoryRule.t()]) :: result() | {:error, :missing_columns}
  def process(csv_content, category_rules) do
    case Parser.parse_string(csv_content, skip_headers: false) do
      [header | rows] ->
        case column_index(header) do
          {:ok, index} -> process_rows(rows, index, category_rules)
          :error -> {:error, :missing_columns}
        end

      [] ->
        %{transactions: [], rows_total: 0, rows_errored: 0, error_details: []}
    end
  end

  defp column_index(header) do
    normalized = Enum.map(header, &(&1 |> String.trim() |> String.downcase()))

    if Enum.all?(@required_columns, &(&1 in normalized)) do
      {:ok,
       %{
         date: Enum.find_index(normalized, &(&1 == "date")),
         description: Enum.find_index(normalized, &(&1 == "description")),
         amount: Enum.find_index(normalized, &(&1 == "amount"))
       }}
    else
      :error
    end
  end

  defp process_rows(rows, index, category_rules) do
    # Row 1 is the header, so the first data row is row 2 — matching
    # what a user would count looking at the file in a spreadsheet.
    rows
    |> Enum.with_index(2)
    |> Enum.reduce(%{transactions: [], rows_errored: 0, error_details: []}, fn {row, line}, acc ->
      case parse_row(row, index) do
        {:ok, attrs} ->
          transaction = attrs |> put_fingerprint() |> put_category(category_rules)
          %{acc | transactions: [transaction | acc.transactions]}

        {:error, reason} ->
          %{
            acc
            | rows_errored: acc.rows_errored + 1,
              error_details: [%{row: line, reason: reason} | acc.error_details]
          }
      end
    end)
    |> finalize(length(rows))
  end

  defp finalize(acc, rows_total) do
    %{
      transactions: Enum.reverse(acc.transactions),
      rows_total: rows_total,
      rows_errored: acc.rows_errored,
      error_details: Enum.reverse(acc.error_details)
    }
  end

  defp parse_row(row, index) do
    with {:ok, date} <- fetch_date(Enum.at(row, index.date)),
         {:ok, description} <- fetch_description(Enum.at(row, index.description)),
         {:ok, amount_cents} <- fetch_amount(Enum.at(row, index.amount)) do
      {:ok, %{posted_on: date, description: description, amount_cents: amount_cents}}
    end
  end

  defp fetch_date(value) when is_binary(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:error, "invalid date #{inspect(value)}, expected YYYY-MM-DD"}
    end
  end

  defp fetch_date(_), do: {:error, "missing date"}

  defp fetch_description(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, "missing description"}
      description -> {:ok, description}
    end
  end

  defp fetch_description(_), do: {:error, "missing description"}

  defp fetch_amount(value) when is_binary(value) do
    case Regex.run(@amount_pattern, String.trim(value)) do
      [_, sign, dollars, cents] ->
        whole = dollars |> String.replace(",", "") |> String.to_integer()
        amount_cents = whole * 100 + String.to_integer(cents)
        {:ok, if(sign == "-", do: -amount_cents, else: amount_cents)}

      nil ->
        {:error, "invalid amount #{inspect(value)}, expected a decimal like -4.50"}
    end
  end

  defp fetch_amount(_), do: {:error, "missing amount"}

  defp put_fingerprint(
         %{posted_on: posted_on, amount_cents: amount_cents, description: description} = attrs
       ) do
    Map.put(attrs, :fingerprint, Transaction.fingerprint(posted_on, amount_cents, description))
  end

  defp put_category(attrs, category_rules) do
    merchant = normalize_merchant(attrs.description)
    downcased_merchant = String.downcase(merchant)

    category =
      Enum.find_value(category_rules, fn rule ->
        if String.contains?(downcased_merchant, String.downcase(rule.match_text)),
          do: rule.category
      end)

    attrs
    |> Map.put(:normalized_merchant, merchant)
    |> Map.put(:category, category)
  end

  @doc """
  Strips a trailing reference/store number and collapses whitespace from
  a raw statement description, then title-cases what's left — e.g.
  `"COFFEE SHOP 1234"` becomes `"Coffee Shop"`. Used both for category
  matching and as the friendlier merchant name shown in the UI.
  """
  @spec normalize_merchant(String.t()) :: String.t()
  def normalize_merchant(description) do
    description
    |> String.replace(~r/\s+\d+\s*$/, "")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
