defmodule TallyWeb.AccountLive.Index do
  use TallyWeb, :live_view

  alias Tally.Finance
  alias Tally.Finance.Account

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :accounts, list_accounts_with_balance(socket.assigns.current_user))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket |> assign(:page_title, "Accounts") |> assign(:account, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket |> assign(:page_title, "New Account") |> assign(:account, %Account{})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Accounts
      <:subtitle>Every account you're tracking, with its current balance.</:subtitle>
      <:actions>
        <.link patch={~p"/accounts/new"}>
          <.button>New account</.button>
        </.link>
      </:actions>
    </.header>

    <.table
      id="accounts"
      rows={@accounts}
      row_click={fn row -> JS.navigate(~p"/accounts/#{row.account}") end}
    >
      <:col :let={row} label="Name">{row.account.name}</:col>
      <:col :let={row} label="Type">{account_type_label(row.account.type)}</:col>
      <:col :let={row} label="Balance">
        <span class={row.balance_cents < 0 && "text-red-700"}>{format_cents(row.balance_cents)}</span>
      </:col>
    </.table>

    <p :if={@accounts == []} class="mt-6 text-sm text-zinc-500">
      No accounts yet. Add one to start importing a statement.
    </p>

    <.modal :if={@live_action == :new} id="account-modal" show on_cancel={JS.patch(~p"/accounts")}>
      <.live_component
        module={TallyWeb.AccountLive.FormComponent}
        id={:new}
        title={@page_title}
        action={@live_action}
        account={@account}
        current_user={@current_user}
        patch={~p"/accounts"}
      />
    </.modal>
    """
  end

  @impl true
  def handle_info({TallyWeb.AccountLive.FormComponent, {:saved, _account}}, socket) do
    {:noreply, assign(socket, :accounts, list_accounts_with_balance(socket.assigns.current_user))}
  end

  defp list_accounts_with_balance(user) do
    user
    |> Finance.list_accounts()
    |> Enum.map(&%{account: &1, balance_cents: Finance.account_balance(&1)})
  end

  defp account_type_label(:checking), do: "Checking"
  defp account_type_label(:credit_card), do: "Credit card"

  defp format_cents(cents), do: TallyWeb.Money.format(cents)
end
