defmodule Tally.FinanceFixtures do
  @moduledoc """
  This module defines test helpers for creating entities via the
  `Tally.Finance` context.
  """

  alias Tally.Finance

  import Tally.AccountsFixtures

  def valid_account_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{name: "Everyday Checking", type: :checking})
  end

  @doc "Creates an account, defaulting to a fresh user if one isn't given."
  def account_fixture(attrs \\ %{}, user \\ nil) do
    user = user || user_fixture()

    {:ok, account} = Finance.create_account(user, valid_account_attributes(attrs))
    account
  end

  def valid_transaction_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      posted_on: ~D[2026-01-15],
      description: "COFFEE SHOP 1234",
      amount_cents: -450
    })
  end

  def transaction_fixture(user, account, attrs \\ %{}) do
    {:ok, transaction} =
      Finance.create_transaction(user, account, valid_transaction_attributes(attrs))

    transaction
  end

  def valid_category_rule_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{match_text: "NETFLIX", category: "Subscriptions"})
  end

  def category_rule_fixture(user, attrs \\ %{}) do
    {:ok, rule} = Finance.create_category_rule(user, valid_category_rule_attributes(attrs))
    rule
  end
end
