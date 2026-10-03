defmodule TallyWeb.Money do
  @moduledoc """
  Formats integer cents as a dollar string, e.g. `-450` -> `"-$4.50"`.
  The only place in the web layer that turns `amount_cents` into text —
  see CLAUDE.md on why storage and arithmetic never touch a float.
  """

  @doc "Formats `cents` as a signed dollar amount."
  @spec format(integer()) :: String.t()
  def format(cents) when is_integer(cents) do
    sign = if cents < 0, do: "-", else: ""
    whole = cents |> abs() |> div(100)
    fraction = cents |> abs() |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")

    "#{sign}$#{format_thousands(whole)}.#{fraction}"
  end

  defp format_thousands(whole) do
    whole
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
