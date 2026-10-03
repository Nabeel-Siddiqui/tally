defmodule TallyWeb.AccountLive.ShowTest do
  use TallyWeb.ConnCase, async: true
  use Oban.Testing, repo: Tally.Repo

  import Phoenix.LiveViewTest
  import Tally.FinanceFixtures

  setup :register_and_log_in_user

  describe "Show" do
    test "renders the account name, balance, and transactions", %{conn: conn, user: user} do
      account = account_fixture(%{name: "Everyday Checking"}, user)
      transaction_fixture(user, account, %{description: "Coffee Shop", amount_cents: -450})

      {:ok, _view, html} = live(conn, ~p"/accounts/#{account}")

      assert html =~ "Everyday Checking"
      assert html =~ "-$4.50"
      assert html =~ "Coffee Shop"
    end

    test "shows empty states with no transactions or category spending", %{conn: conn, user: user} do
      account = account_fixture(%{}, user)

      {:ok, _view, html} = live(conn, ~p"/accounts/#{account}")

      assert html =~ "No transactions yet"
      assert html =~ "No spending recorded yet this month"
      assert html =~ "$0.00"
    end

    test "shows this month's category breakdown", %{conn: conn, user: user} do
      account = account_fixture(%{}, user)
      today = Date.utc_today()

      transaction_fixture(user, account, %{
        description: "Netflix",
        amount_cents: -1500,
        category: "Subscriptions",
        posted_on: today
      })

      {:ok, _view, html} = live(conn, ~p"/accounts/#{account}")

      assert html =~ "Subscriptions"
      assert html =~ "-$15.00"
    end

    test "redirects to the accounts list for another user's account", %{conn: conn} do
      other = Tally.AccountsFixtures.user_fixture()
      theirs = account_fixture(%{}, other)

      assert {:error, {:live_redirect, %{to: "/accounts"}}} = live(conn, ~p"/accounts/#{theirs}")
    end

    test "redirects to the accounts list for a nonexistent account", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/accounts"}}} = live(conn, ~p"/accounts/999999")
    end

    test "uploading a CSV imports it and the dashboard updates live, no reload", %{
      conn: conn,
      user: user
    } do
      account = account_fixture(%{}, user)
      {:ok, view, _html} = live(conn, ~p"/accounts/#{account}")

      csv = "date,description,amount\n2026-01-15,Coffee Shop,-4.50\n2026-01-16,Paycheck,1200.00\n"

      file =
        file_input(view, "#upload-form", :csv, [
          %{name: "statement.csv", content: csv, type: "text/csv"}
        ])

      assert render_upload(file, "statement.csv") =~ "statement.csv"

      view
      |> form("#upload-form")
      |> render_submit()

      assert render(view) =~ "Importing statement.csv"

      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :imports)

      html = render(view)
      assert html =~ "Import finished: 2 added, 0 duplicate(s) skipped, 0 row(s) had errors."
      assert html =~ "Coffee Shop"
      assert html =~ "Paycheck"
      assert html =~ "$1,195.50"
    end

    test "an import with row errors reports them without crashing the page", %{
      conn: conn,
      user: user
    } do
      account = account_fixture(%{}, user)
      {:ok, view, _html} = live(conn, ~p"/accounts/#{account}")

      csv = "date,description,amount\n2026-01-15,Coffee,-4.50\nnot-a-date,Lunch,-12.00\n"

      file =
        file_input(view, "#upload-form", :csv, [%{name: "x.csv", content: csv, type: "text/csv"}])

      render_upload(file, "x.csv")
      view |> form("#upload-form") |> render_submit()

      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :imports)

      assert render(view) =~ "1 row(s) had errors"
    end
  end
end
