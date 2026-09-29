defmodule Tally.FinanceTest do
  use Tally.DataCase, async: true

  import Tally.AccountsFixtures
  import Tally.FinanceFixtures

  alias Tally.Finance
  alias Tally.Finance.Transaction

  describe "create_account/2" do
    test "creates an account owned by the user" do
      user = user_fixture()

      assert {:ok, account} = Finance.create_account(user, %{name: "Checking", type: :checking})
      assert account.name == "Checking"
      assert account.type == :checking
      assert account.user_id == user.id
    end

    test "requires a name and a type" do
      user = user_fixture()

      assert {:error, changeset} = Finance.create_account(user, %{})
      assert "can't be blank" in errors_on(changeset).name
      assert "can't be blank" in errors_on(changeset).type
    end

    test "rejects a type outside checking/credit_card" do
      user = user_fixture()

      assert {:error, changeset} =
               Finance.create_account(user, %{name: "Checking", type: :savings})

      assert "is invalid" in errors_on(changeset).type
    end
  end

  describe "get_account/2" do
    test "returns the account when owned by the user" do
      user = user_fixture()
      account = account_fixture(%{}, user)

      assert {:ok, ^account} = Finance.get_account(user, account.id)
    end

    test "returns :not_found for another user's account" do
      owner = user_fixture()
      other = user_fixture()
      account = account_fixture(%{}, owner)

      assert {:error, :not_found} = Finance.get_account(other, account.id)
    end

    test "returns :not_found for a malformed id instead of raising" do
      user = user_fixture()

      assert {:error, :not_found} = Finance.get_account(user, "not-an-id")
    end
  end

  describe "list_accounts/1" do
    test "lists only the user's own accounts, newest first" do
      user = user_fixture()
      other = user_fixture()

      older = account_fixture(%{name: "Older"}, user)
      newer = account_fixture(%{name: "Newer"}, user)
      _theirs = account_fixture(%{name: "Not mine"}, other)

      assert Finance.list_accounts(user) |> Enum.map(& &1.id) == [newer.id, older.id]
    end
  end

  describe "update_account/3" do
    test "updates an owned account" do
      user = user_fixture()
      account = account_fixture(%{name: "Old name"}, user)

      assert {:ok, updated} = Finance.update_account(user, account, %{name: "New name"})
      assert updated.name == "New name"
    end

    test "refuses to update another user's account" do
      owner = user_fixture()
      other = user_fixture()
      account = account_fixture(%{name: "Original"}, owner)

      assert {:error, :not_found} = Finance.update_account(other, account, %{name: "Hijacked"})
    end
  end

  describe "create_import/3" do
    test "creates an import for an owned account" do
      user = user_fixture()
      account = account_fixture(%{}, user)

      assert {:ok, import} = Finance.create_import(user, account, %{filename: "jan.csv"})
      assert import.filename == "jan.csv"
      assert import.status == :pending
      assert import.account_id == account.id
    end

    test "refuses to create an import on another user's account" do
      owner = user_fixture()
      other = user_fixture()
      account = account_fixture(%{}, owner)

      assert {:error, :not_found} = Finance.create_import(other, account, %{filename: "x.csv"})
    end
  end

  describe "create_transaction/3 — validations and money handling" do
    test "creates a transaction with a negative amount for spending" do
      user = user_fixture()
      account = account_fixture(%{}, user)

      assert {:ok, txn} =
               Finance.create_transaction(user, account, %{
                 posted_on: ~D[2026-02-01],
                 description: "Coffee",
                 amount_cents: -375
               })

      assert txn.amount_cents == -375
      assert is_integer(txn.amount_cents)
    end

    test "creates a transaction with a positive amount for a credit" do
      user = user_fixture()
      account = account_fixture(%{}, user)

      assert {:ok, txn} =
               Finance.create_transaction(user, account, %{
                 posted_on: ~D[2026-02-01],
                 description: "Refund",
                 amount_cents: 1200
               })

      assert txn.amount_cents == 1200
    end

    test "requires posted_on, description, and amount_cents" do
      user = user_fixture()
      account = account_fixture(%{}, user)

      assert {:error, changeset} = Finance.create_transaction(user, account, %{})
      errors = errors_on(changeset)
      assert "can't be blank" in errors.posted_on
      assert "can't be blank" in errors.description
      assert "can't be blank" in errors.amount_cents
    end

    test "refuses to create a transaction on another user's account" do
      owner = user_fixture()
      other = user_fixture()
      account = account_fixture(%{}, owner)

      assert {:error, :not_found} =
               Finance.create_transaction(other, account, valid_transaction_attributes())
    end
  end

  describe "create_transaction/3 — duplicate prevention" do
    test "computes the same fingerprint automatically, without the caller providing one" do
      user = user_fixture()
      account = account_fixture(%{}, user)

      {:ok, txn} =
        Finance.create_transaction(
          user,
          account,
          valid_transaction_attributes(%{
            posted_on: ~D[2026-01-15],
            description: "COFFEE SHOP",
            amount_cents: -450
          })
        )

      assert txn.fingerprint ==
               Transaction.fingerprint(~D[2026-01-15], -450, "COFFEE SHOP")
    end

    test "rejects an exact duplicate on the same account (re-uploaded overlapping statement)" do
      user = user_fixture()
      account = account_fixture(%{}, user)
      attrs = valid_transaction_attributes()

      assert {:ok, _first} = Finance.create_transaction(user, account, attrs)

      assert {:error, changeset} = Finance.create_transaction(user, account, attrs)
      assert "has already been taken" in errors_on(changeset).fingerprint
    end

    test "the same transaction on a different account is not a duplicate" do
      user = user_fixture()
      checking = account_fixture(%{name: "Checking"}, user)
      credit = account_fixture(%{name: "Credit"}, user)
      attrs = valid_transaction_attributes()

      assert {:ok, _} = Finance.create_transaction(user, checking, attrs)
      assert {:ok, _} = Finance.create_transaction(user, credit, attrs)
    end

    test "a different amount on the same date/description is not treated as a duplicate" do
      user = user_fixture()
      account = account_fixture(%{}, user)

      assert {:ok, _} =
               Finance.create_transaction(
                 user,
                 account,
                 valid_transaction_attributes(%{amount_cents: -450})
               )

      assert {:ok, _} =
               Finance.create_transaction(
                 user,
                 account,
                 valid_transaction_attributes(%{amount_cents: -451})
               )
    end
  end

  describe "list_transactions/1" do
    test "lists an account's transactions, newest first" do
      user = user_fixture()
      account = account_fixture(%{}, user)

      older = transaction_fixture(user, account, %{posted_on: ~D[2026-01-01]})
      newer = transaction_fixture(user, account, %{posted_on: ~D[2026-01-10]})

      assert Finance.list_transactions(account) |> Enum.map(& &1.id) == [newer.id, older.id]
    end

    test "doesn't include another account's transactions" do
      user = user_fixture()
      mine = account_fixture(%{name: "Mine"}, user)
      theirs = account_fixture(%{name: "Theirs"}, user)

      _other = transaction_fixture(user, theirs)
      mine_txn = transaction_fixture(user, mine)

      assert Finance.list_transactions(mine) |> Enum.map(& &1.id) == [mine_txn.id]
    end
  end

  describe "create_category_rule/2" do
    test "creates a rule owned by the user" do
      user = user_fixture()

      assert {:ok, rule} =
               Finance.create_category_rule(user, %{
                 match_text: "NETFLIX",
                 category: "Subscriptions"
               })

      assert rule.match_text == "NETFLIX"
      assert rule.category == "Subscriptions"
    end

    test "trims match_text" do
      user = user_fixture()

      assert {:ok, rule} =
               Finance.create_category_rule(user, %{
                 match_text: "  NETFLIX  ",
                 category: "Subscriptions"
               })

      assert rule.match_text == "NETFLIX"
    end

    test "rejects a second rule with the same match_text for the same user" do
      user = user_fixture()
      _first = category_rule_fixture(user, %{match_text: "NETFLIX"})

      assert {:error, changeset} =
               Finance.create_category_rule(user, %{
                 match_text: "NETFLIX",
                 category: "Entertainment"
               })

      assert "has already been taken" in errors_on(changeset).match_text
    end

    test "the same match_text is fine for a different user" do
      user_a = user_fixture()
      user_b = user_fixture()
      _rule_a = category_rule_fixture(user_a, %{match_text: "NETFLIX"})

      assert {:ok, _rule_b} =
               Finance.create_category_rule(user_b, %{
                 match_text: "NETFLIX",
                 category: "Subscriptions"
               })
    end
  end

  describe "list_category_rules/1" do
    test "lists only the user's own rules" do
      user = user_fixture()
      other = user_fixture()

      mine = category_rule_fixture(user, %{match_text: "NETFLIX"})
      _theirs = category_rule_fixture(other, %{match_text: "SPOTIFY"})

      assert Finance.list_category_rules(user) |> Enum.map(& &1.id) == [mine.id]
    end
  end

  describe "Transaction.fingerprint/3" do
    test "is deterministic for the same inputs" do
      a = Transaction.fingerprint(~D[2026-01-15], -450, "Coffee Shop")
      b = Transaction.fingerprint(~D[2026-01-15], -450, "Coffee Shop")

      assert a == b
    end

    test "normalizes case and surrounding whitespace in the description" do
      a = Transaction.fingerprint(~D[2026-01-15], -450, "COFFEE SHOP")
      b = Transaction.fingerprint(~D[2026-01-15], -450, "  coffee shop  ")

      assert a == b
    end

    test "differs when the date, amount, or description differs" do
      base = Transaction.fingerprint(~D[2026-01-15], -450, "Coffee Shop")

      assert Transaction.fingerprint(~D[2026-01-16], -450, "Coffee Shop") != base
      assert Transaction.fingerprint(~D[2026-01-15], -451, "Coffee Shop") != base
      assert Transaction.fingerprint(~D[2026-01-15], -450, "Coffee Shop 2") != base
    end
  end
end
