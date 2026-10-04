defmodule Tally.SeedsTest do
  use Tally.DataCase, async: false

  import ExUnit.CaptureIO

  alias Tally.Finance.{Account, Transaction}
  alias Tally.Repo

  @seeds_path Path.expand("../../priv/repo/seeds.exs", __DIR__)

  test "seeding twice leaves the database exactly as seeding once did" do
    capture_io(fn -> Code.eval_file(@seeds_path) end)

    accounts_after_first = Repo.aggregate(Account, :count)
    transactions_after_first = Repo.aggregate(Transaction, :count)

    assert accounts_after_first == 2
    assert transactions_after_first == 78

    capture_io(fn -> Code.eval_file(@seeds_path) end)

    assert Repo.aggregate(Account, :count) == accounts_after_first
    assert Repo.aggregate(Transaction, :count) == transactions_after_first
  end
end
