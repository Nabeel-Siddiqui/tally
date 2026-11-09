defmodule Tally.Money do
  @moduledoc """
  Parsing a dollar-and-cents string into integer cents (see CLAUDE.md
  on why money is never a float). The one place this parsing happens,
  used both by CSV import (`Tally.Finance.Importer`) and anywhere a
  person types a dollar amount directly (an account's opening
  balance), so the two can never disagree about what counts as a
  valid amount.
  """

  @pattern ~r/^(-?)\$?([\d,]+)\.(\d{2})$/

  @doc """
  Parses a decimal dollar string with exactly two decimal places —
  `"-4.50"`, `"$1,200.00"` — into integer cents. Returns `:error` for
  anything else (a float with the wrong number of decimal places, a
  non-numeric string) rather than guessing at what was meant.
  """
  @spec parse_cents(String.t()) :: {:ok, integer()} | :error
  def parse_cents(value) when is_binary(value) do
    case Regex.run(@pattern, String.trim(value)) do
      [_, sign, dollars, cents] ->
        whole = dollars |> String.replace(",", "") |> String.to_integer()
        amount_cents = whole * 100 + String.to_integer(cents)
        {:ok, if(sign == "-", do: -amount_cents, else: amount_cents)}

      nil ->
        :error
    end
  end
end
