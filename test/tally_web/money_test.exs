defmodule TallyWeb.MoneyTest do
  use ExUnit.Case, async: true

  alias TallyWeb.Money

  test "formats a positive amount" do
    assert Money.format(450) == "$4.50"
  end

  test "formats a negative amount with a leading minus" do
    assert Money.format(-450) == "-$4.50"
  end

  test "formats zero" do
    assert Money.format(0) == "$0.00"
  end

  test "pads a single-digit cents value" do
    assert Money.format(405) == "$4.05"
  end

  test "inserts a thousands separator" do
    assert Money.format(123_456_789) == "$1,234,567.89"
  end

  test "handles a negative amount with a thousands separator" do
    assert Money.format(-150_000) == "-$1,500.00"
  end
end
