defmodule Tally.FinanceTest do
  use Tally.DataCase, async: true
  use Oban.Testing, repo: Tally.Repo

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

  describe "get_import/2" do
    test "returns the import when it belongs to the given account" do
      user = user_fixture()
      account = account_fixture(%{}, user)
      {:ok, import} = Finance.create_import(user, account, %{filename: "jan.csv"})

      assert {:ok, ^import} = Finance.get_import(account, import.id)
    end

    test "returns :not_found for another account's import" do
      user = user_fixture()
      mine = account_fixture(%{name: "Mine"}, user)
      theirs = account_fixture(%{name: "Theirs"}, user)
      {:ok, import} = Finance.create_import(user, theirs, %{filename: "jan.csv"})

      assert {:error, :not_found} = Finance.get_import(mine, import.id)
    end

    test "returns :not_found for a malformed id instead of raising" do
      user = user_fixture()
      account = account_fixture(%{}, user)

      assert {:error, :not_found} = Finance.get_import(account, "not-an-id")
    end
  end

  describe "run_import/4" do
    test "bulk-inserts valid rows and marks the import completed" do
      user = user_fixture()
      account = account_fixture(%{}, user)
      {:ok, import} = Finance.create_import(user, account, %{filename: "jan.csv"})

      csv = "date,description,amount\n2026-01-15,Coffee,-4.50\n2026-01-16,Paycheck,1200.00\n"

      assert {:ok, updated} = Finance.run_import(user, account, import, csv)
      assert updated.status == :completed
      assert updated.rows_total == 2
      assert updated.rows_imported == 2
      assert updated.rows_skipped == 0
      assert updated.rows_errored == 0

      assert [_first, _second] = Finance.list_transactions(account)
    end

    test "applies the user's category rules to imported transactions" do
      user = user_fixture()
      account = account_fixture(%{}, user)
      _rule = category_rule_fixture(user, %{match_text: "netflix", category: "Subscriptions"})
      {:ok, import} = Finance.create_import(user, account, %{filename: "jan.csv"})

      csv = "date,description,amount\n2026-01-15,NETFLIX.COM 8829,-15.99\n"

      assert {:ok, _updated} = Finance.run_import(user, account, import, csv)
      assert [txn] = Finance.list_transactions(account)
      assert txn.category == "Subscriptions"
      assert txn.normalized_merchant == "Netflix.com"
    end

    test "skips an exact duplicate already on the account instead of erroring the import" do
      user = user_fixture()
      account = account_fixture(%{}, user)

      _existing =
        transaction_fixture(user, account, %{
          posted_on: ~D[2026-01-15],
          description: "Coffee",
          amount_cents: -450
        })

      {:ok, import} = Finance.create_import(user, account, %{filename: "jan.csv"})

      csv = "date,description,amount\n2026-01-15,Coffee,-4.50\n2026-01-16,Lunch,-12.00\n"

      assert {:ok, updated} = Finance.run_import(user, account, import, csv)
      assert updated.rows_total == 2
      assert updated.rows_imported == 1
      assert updated.rows_skipped == 1
      assert updated.rows_errored == 0
      assert length(Finance.list_transactions(account)) == 2
    end

    test "records malformed rows on the import without failing the whole batch" do
      user = user_fixture()
      account = account_fixture(%{}, user)
      {:ok, import} = Finance.create_import(user, account, %{filename: "jan.csv"})

      csv = "date,description,amount\n2026-01-15,Coffee,-4.50\nnot-a-date,Lunch,-12.00\n"

      assert {:ok, updated} = Finance.run_import(user, account, import, csv)
      assert updated.rows_imported == 1
      assert updated.rows_errored == 1
      assert [%{row: 3}] = updated.error_details
    end

    test "marks the import failed when the CSV is missing a required column" do
      user = user_fixture()
      account = account_fixture(%{}, user)
      {:ok, import} = Finance.create_import(user, account, %{filename: "jan.csv"})

      csv = "date,amount\n2026-01-15,-4.50\n"

      assert {:ok, updated} = Finance.run_import(user, account, import, csv)
      assert updated.status == :failed
      assert [%{reason: reason}] = updated.error_details
      assert reason =~ "missing a required column"
    end

    test "refuses to run an import against another user's account" do
      owner = user_fixture()
      other = user_fixture()
      account = account_fixture(%{}, owner)
      {:ok, import} = Finance.create_import(owner, account, %{filename: "jan.csv"})

      assert {:error, :not_found} =
               Finance.run_import(other, account, import, "date,description,amount\n")
    end
  end

  describe "process_import_async/4" do
    test "enqueues an ImportWorker job with the import's details" do
      user = user_fixture()
      account = account_fixture(%{}, user)
      {:ok, import} = Finance.create_import(user, account, %{filename: "jan.csv"})

      assert {:ok, _job} =
               Finance.process_import_async(user, account, import, "date,description,amount\n")

      assert_enqueued(
        worker: Tally.Finance.ImportWorker,
        args: %{"user_id" => user.id, "account_id" => account.id, "import_id" => import.id}
      )
    end
  end

  describe "account_balance/1" do
    test "sums every transaction on the account" do
      user = user_fixture()
      account = account_fixture(%{}, user)
      _spend = transaction_fixture(user, account, %{description: "Coffee", amount_cents: -450})
      _credit = transaction_fixture(user, account, %{description: "Refund", amount_cents: 1000})

      assert Finance.account_balance(account) == 550
    end

    test "is 0 for an account with no transactions" do
      user = user_fixture()
      account = account_fixture(%{}, user)

      assert Finance.account_balance(account) == 0
    end
  end

  describe "spending_by_category/3" do
    test "totals spend per category, most-spent first, within the date range" do
      user = user_fixture()
      account = account_fixture(%{}, user)

      transaction_fixture(user, account, %{
        description: "Netflix",
        amount_cents: -1500,
        category: "Subscriptions",
        posted_on: ~D[2026-02-10]
      })

      transaction_fixture(user, account, %{
        description: "Spotify",
        amount_cents: -1000,
        category: "Subscriptions",
        posted_on: ~D[2026-02-11]
      })

      transaction_fixture(user, account, %{
        description: "Groceries",
        amount_cents: -5000,
        category: "Food",
        posted_on: ~D[2026-02-12]
      })

      assert Finance.spending_by_category(account, ~D[2026-02-01], ~D[2026-02-28]) == [
               {"Food", 5000},
               {"Subscriptions", 2500}
             ]
    end

    test "groups uncategorized transactions together instead of dropping them" do
      user = user_fixture()
      account = account_fixture(%{}, user)

      transaction_fixture(user, account, %{
        description: "Mystery charge",
        amount_cents: -200,
        posted_on: ~D[2026-02-10]
      })

      assert Finance.spending_by_category(account, ~D[2026-02-01], ~D[2026-02-28]) == [
               {"Uncategorized", 200}
             ]
    end

    test "excludes credits/refunds and transactions outside the range" do
      user = user_fixture()
      account = account_fixture(%{}, user)

      transaction_fixture(user, account, %{
        description: "Refund",
        amount_cents: 500,
        category: "Food",
        posted_on: ~D[2026-02-10]
      })

      transaction_fixture(user, account, %{
        description: "Last month",
        amount_cents: -500,
        category: "Food",
        posted_on: ~D[2026-01-15]
      })

      assert Finance.spending_by_category(account, ~D[2026-02-01], ~D[2026-02-28]) == []
    end
  end

  describe "monthly_totals/2" do
    test "returns the trailing N months oldest first, including zero-spend months" do
      user = user_fixture()
      account = account_fixture(%{}, user)

      today = Date.utc_today()
      this_month = Date.new!(today.year, today.month, 1)

      transaction_fixture(user, account, %{
        description: "Rent",
        amount_cents: -150_000,
        posted_on: this_month
      })

      result = Finance.monthly_totals(account, 3)

      assert length(result) == 3
      assert List.last(result) == {this_month, 150_000}
      assert Enum.all?(result, fn {month, _total} -> %Date{day: 1} = month end)
    end

    test "defaults to 6 months" do
      user = user_fixture()
      account = account_fixture(%{}, user)

      assert length(Finance.monthly_totals(account)) == 6
    end
  end

  describe "subscribe_to_account/1 and import completion broadcasts" do
    test "a subscriber receives {:import_completed, import} when run_import/4 finishes" do
      user = user_fixture()
      account = account_fixture(%{}, user)
      {:ok, import} = Finance.create_import(user, account, %{filename: "jan.csv"})

      :ok = Finance.subscribe_to_account(account)

      assert {:ok, completed} =
               Finance.run_import(
                 user,
                 account,
                 import,
                 "date,description,amount\n2026-01-15,Coffee,-4.50\n"
               )

      assert_receive {:import_completed, ^completed}
    end

    test "a subscriber is also notified when the import fails" do
      user = user_fixture()
      account = account_fixture(%{}, user)
      {:ok, import} = Finance.create_import(user, account, %{filename: "jan.csv"})

      :ok = Finance.subscribe_to_account(account)

      assert {:ok, failed} =
               Finance.run_import(user, account, import, "date,amount\n2026-01-15,-4.50\n")

      assert_receive {:import_completed, ^failed}
      assert failed.status == :failed
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
