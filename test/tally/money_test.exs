defmodule Tally.MoneyTest do
  use ExUnit.Case, async: true

  alias Tally.Money

  describe "parse_cents/1" do
    test "parses a plain decimal" do
      assert Money.parse_cents("4.50") == {:ok, 450}
    end

    test "parses a negative amount" do
      assert Money.parse_cents("-4.50") == {:ok, -450}
    end

    test "accepts a leading dollar sign" do
      assert Money.parse_cents("$1200.00") == {:ok, 120_000}
    end

    test "accepts comma thousands separators" do
      assert Money.parse_cents("1,200.00") == {:ok, 120_000}
    end

    test "trims surrounding whitespace" do
      assert Money.parse_cents("  4.50  ") == {:ok, 450}
    end

    test "rejects a value with the wrong number of decimal places" do
      assert Money.parse_cents("4.5") == :error
      assert Money.parse_cents("4.500") == :error
    end

    test "rejects a non-numeric string" do
      assert Money.parse_cents("not a number") == :error
    end

    test "rejects an empty string" do
      assert Money.parse_cents("") == :error
    end
  end
end
