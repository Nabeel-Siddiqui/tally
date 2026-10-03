defmodule TallyWeb.AccountLive.IndexTest do
  use TallyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tally.FinanceFixtures

  setup :register_and_log_in_user

  describe "Index" do
    test "lists the user's accounts with their balance", %{conn: conn, user: user} do
      account = account_fixture(%{name: "Everyday Checking"}, user)
      transaction_fixture(user, account, %{amount_cents: -450})

      {:ok, _view, html} = live(conn, ~p"/accounts")

      assert html =~ "Everyday Checking"
      assert html =~ "-$4.50"
    end

    test "shows an empty state with no accounts", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/accounts")

      assert html =~ "No accounts yet"
    end

    test "doesn't show another user's accounts", %{conn: conn} do
      other = Tally.AccountsFixtures.user_fixture()
      _theirs = account_fixture(%{name: "Not mine"}, other)

      {:ok, _view, html} = live(conn, ~p"/accounts")

      refute html =~ "Not mine"
    end

    test "creates a new account", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/accounts")

      view
      |> element(~s|a[href="#{~p"/accounts/new"}"]|)
      |> render_click()

      assert_patch(view, ~p"/accounts/new")

      view
      |> form("#account-form", account: %{name: "Credit Card", type: "credit_card"})
      |> render_submit()

      assert_patch(view, ~p"/accounts")
      assert render(view) =~ "Credit Card"
    end

    test "rejects an account with no name or type", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/accounts/new")

      html =
        view
        |> form("#account-form", account: %{name: "", type: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end

    test "redirects if the user is not logged in" do
      conn = Phoenix.ConnTest.build_conn()
      assert {:error, {:redirect, %{to: "/users/log_in"}}} = live(conn, ~p"/accounts")
    end
  end
end
