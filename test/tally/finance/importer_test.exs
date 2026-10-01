defmodule Tally.Finance.ImporterTest do
  use ExUnit.Case, async: true

  alias Tally.Finance.Importer

  @header "date,description,amount\n"

  describe "process/2 — happy path" do
    test "parses valid rows into transaction attributes" do
      csv = @header <> "2026-01-15,COFFEE SHOP 1234,-4.50\n2026-01-16,PAYCHECK,1200.00\n"

      result = Importer.process(csv, [])

      assert result.rows_total == 2
      assert result.rows_errored == 0
      assert result.error_details == []

      assert [first, second] = result.transactions
      assert first.posted_on == ~D[2026-01-15]
      assert first.description == "COFFEE SHOP 1234"
      assert first.amount_cents == -450
      assert second.amount_cents == 120_000
    end

    test "column order doesn't matter, and matching is case-insensitive" do
      csv = "Amount,Date,Description\n-4.50,2026-01-15,Coffee\n"

      assert %{transactions: [txn]} = Importer.process(csv, [])
      assert txn.posted_on == ~D[2026-01-15]
      assert txn.amount_cents == -450
    end

    test "extra columns are ignored" do
      csv = "date,description,amount,account_number\n2026-01-15,Coffee,-4.50,****1234\n"

      assert %{transactions: [txn]} = Importer.process(csv, [])
      assert txn.description == "Coffee"
    end

    test "an empty file (no rows at all) produces an empty, zero-count result" do
      assert Importer.process("", []) == %{
               transactions: [],
               rows_total: 0,
               rows_errored: 0,
               error_details: []
             }
    end

    test "a header with no data rows produces zero rows, not an error" do
      assert %{transactions: [], rows_total: 0, rows_errored: 0} = Importer.process(@header, [])
    end
  end

  describe "process/2 — missing columns" do
    test "returns an error tuple when a required column is absent" do
      csv = "date,amount\n2026-01-15,-4.50\n"

      assert Importer.process(csv, []) == {:error, :missing_columns}
    end
  end

  describe "process/2 — row-level errors" do
    test "an invalid date is reported with its row number, not raised" do
      csv = @header <> "not-a-date,Coffee,-4.50\n"

      assert %{transactions: [], rows_total: 1, rows_errored: 1, error_details: [error]} =
               Importer.process(csv, [])

      assert error.row == 2
      assert error.reason =~ "invalid date"
    end

    test "an invalid amount is reported with its row number" do
      csv = @header <> "2026-01-15,Coffee,four fifty\n"

      assert %{error_details: [error]} = Importer.process(csv, [])
      assert error.reason =~ "invalid amount"
    end

    test "a whole-number amount without cents is rejected rather than guessed at" do
      csv = @header <> "2026-01-15,Coffee,100\n"

      assert %{rows_errored: 1} = Importer.process(csv, [])
    end

    test "a blank description is reported" do
      csv = @header <> "2026-01-15,,-4.50\n"

      assert %{error_details: [error]} = Importer.process(csv, [])
      assert error.reason =~ "missing description"
    end

    test "one bad row among good ones is isolated — the rest still import" do
      csv =
        @header <> "2026-01-15,Coffee,-4.50\nnot-a-date,Lunch,-12.00\n2026-01-17,Rent,-1500.00\n"

      result = Importer.process(csv, [])

      assert result.rows_total == 3
      assert result.rows_errored == 1
      assert length(result.transactions) == 2
      assert [%{row: 3}] = result.error_details
    end
  end

  describe "process/2 — fingerprinting" do
    alias Tally.Finance.Transaction

    test "each transaction gets the same fingerprint Transaction.changeset/2 would compute" do
      csv = @header <> "2026-01-15,Coffee,-4.50\n"

      assert [txn] = Importer.process(csv, []).transactions
      assert txn.fingerprint == Transaction.fingerprint(~D[2026-01-15], -450, "Coffee")
    end
  end

  describe "process/2 — category matching" do
    alias Tally.Finance.CategoryRule

    test "assigns the category of the first rule whose match_text is in the merchant" do
      csv = @header <> "2026-01-15,NETFLIX.COM 8829,-15.99\n"
      rules = [%CategoryRule{match_text: "netflix", category: "Subscriptions"}]

      assert [txn] = Importer.process(csv, rules).transactions
      assert txn.category == "Subscriptions"
    end

    test "leaves category nil when no rule matches" do
      csv = @header <> "2026-01-15,Some Random Store,-15.99\n"
      rules = [%CategoryRule{match_text: "netflix", category: "Subscriptions"}]

      assert [txn] = Importer.process(csv, rules).transactions
      assert txn.category == nil
    end

    test "matching is case-insensitive against the normalized merchant" do
      csv = @header <> "2026-01-15,netflix.com 8829,-15.99\n"
      rules = [%CategoryRule{match_text: "NETFLIX", category: "Subscriptions"}]

      assert [txn] = Importer.process(csv, rules).transactions
      assert txn.category == "Subscriptions"
    end
  end

  describe "normalize_merchant/1" do
    test "strips a trailing reference number" do
      assert Importer.normalize_merchant("COFFEE SHOP 1234") == "Coffee Shop"
    end

    test "collapses extra whitespace and title-cases" do
      assert Importer.normalize_merchant("  THE   coffee SHOP  ") == "The Coffee Shop"
    end

    test "leaves a description with no trailing number alone, aside from casing" do
      assert Importer.normalize_merchant("NETFLIX.COM") == "Netflix.com"
    end
  end
end
