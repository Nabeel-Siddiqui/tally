defmodule TallyWeb.CategoryRuleLive.IndexTest do
  use TallyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tally.FinanceFixtures

  setup :register_and_log_in_user

  describe "Index" do
    test "lists the user's category rules", %{conn: conn, user: user} do
      category_rule_fixture(user, %{match_text: "NETFLIX", category: "Subscriptions"})

      {:ok, _view, html} = live(conn, ~p"/rules")

      assert html =~ "NETFLIX"
      assert html =~ "Subscriptions"
    end

    test "shows an empty state with no rules", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/rules")

      assert html =~ "No rules yet"
    end

    test "doesn't show another user's rules", %{conn: conn} do
      other = Tally.AccountsFixtures.user_fixture()
      category_rule_fixture(other, %{match_text: "SPOTIFY"})

      {:ok, _view, html} = live(conn, ~p"/rules")

      refute html =~ "SPOTIFY"
    end

    test "creates a new rule", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/rules/new")

      view
      |> form("#category-rule-form",
        category_rule: %{match_text: "SPOTIFY", category: "Subscriptions"}
      )
      |> render_submit()

      assert_patch(view, ~p"/rules")
      assert render(view) =~ "SPOTIFY"
    end

    test "rejects a second rule with the same match_text", %{conn: conn, user: user} do
      category_rule_fixture(user, %{match_text: "NETFLIX"})

      {:ok, view, _html} = live(conn, ~p"/rules/new")

      html =
        view
        |> form("#category-rule-form", category_rule: %{match_text: "NETFLIX", category: "Other"})
        |> render_submit()

      assert html =~ "has already been taken"
    end

    test "redirects if the user is not logged in" do
      conn = Phoenix.ConnTest.build_conn()
      assert {:error, {:redirect, %{to: "/users/log_in"}}} = live(conn, ~p"/rules")
    end
  end
end
