defmodule TallyWeb.AccountLive.Show do
  @moduledoc """
  The per-account dashboard: balance, this month's spending by category,
  the trailing 6-month trend, a CSV upload, and the transaction list.

  Uploading a CSV kicks off `Finance.process_import_async/4` and the
  page subscribes to the account's topic (`Finance.subscribe_to_account/1`)
  so the result — however long the background job actually takes —
  shows up here live, with no polling and no reload.
  """

  use TallyWeb, :live_view

  alias Tally.Finance

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Finance.get_account(socket.assigns.current_user, id) do
      {:ok, account} ->
        if connected?(socket), do: Finance.subscribe_to_account(account)

        {:ok,
         socket
         |> assign(:account, account)
         |> assign(:active_import, nil)
         |> assign(:page_title, account.name)
         |> load_dashboard_data()
         |> allow_upload(:csv, accept: ~w(.csv), max_entries: 1, max_file_size: 5_000_000)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That account doesn't exist.")
         |> push_navigate(to: ~p"/accounts")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      {@account.name}
      <:subtitle>{account_type_label(@account.type)}</:subtitle>
      <:actions>
        <.back navigate={~p"/accounts"}>Back to accounts</.back>
      </:actions>
    </.header>

    <p class="mt-4 text-3xl font-semibold text-zinc-900">
      {TallyWeb.Money.format(@balance_cents)}
    </p>

    <.header class="mt-10">Import a statement</.header>
    <form id="upload-form" phx-submit="import" phx-change="validate-upload">
      <.live_file_input upload={@uploads.csv} />
      <.button type="submit" phx-disable-with="Importing...">Import</.button>

      <p :for={entry <- @uploads.csv.entries} class="mt-2 text-sm text-zinc-600">
        {entry.client_name} ({entry.progress}%)
      </p>
      <p :for={{_ref, message} <- @uploads.csv.errors} class="mt-2 text-sm text-red-600">
        {upload_error_message(message)}
      </p>
    </form>
    <p
      :if={@active_import && @active_import.status in [:pending, :processing]}
      class="mt-2 text-sm text-zinc-600"
    >
      Importing {@active_import.filename}…
    </p>

    <.header class="mt-10">This month's spending by category</.header>
    <div :if={@category_breakdown != []} class="mt-4 max-w-xl space-y-3">
      <div :for={{category, cents} <- @category_breakdown}>
        <div class="flex items-baseline justify-between text-sm text-zinc-900">
          <span>{category}</span>
          <span class="font-semibold">{TallyWeb.Money.format(-cents)}</span>
        </div>
        <div class="mt-1 h-3 rounded bg-zinc-100">
          <div
            class="h-3 rounded bg-zinc-900"
            style={"width: #{category_bar_width(cents, @category_breakdown)}%"}
          />
        </div>
      </div>
    </div>
    <p :if={@category_breakdown == []} class="mt-4 text-sm text-zinc-500">
      No spending recorded yet this month.
    </p>

    <.header class="mt-10">Spending trend (last 6 months)</.header>
    <div class="mt-4 max-w-xl space-y-3">
      <div :for={{month, cents} <- @monthly_trend}>
        <div class="flex items-baseline justify-between text-sm text-zinc-900">
          <span>{Calendar.strftime(month, "%B %Y")}</span>
          <span class="font-semibold">{TallyWeb.Money.format(-cents)}</span>
        </div>
        <div class="mt-1 h-3 rounded bg-zinc-100">
          <div
            class="h-3 rounded bg-zinc-900"
            style={"width: #{trend_bar_width(cents, @monthly_trend)}%"}
          />
        </div>
      </div>
    </div>

    <.header class="mt-10">Transactions</.header>
    <.table id="transactions" rows={@streams.transactions}>
      <:col :let={{_id, txn}} label="Date">{txn.posted_on}</:col>
      <:col :let={{_id, txn}} label="Description">{txn.description}</:col>
      <:col :let={{_id, txn}} label="Category">{txn.category || "Uncategorized"}</:col>
      <:col :let={{_id, txn}} label="Amount">
        <span class={txn.amount_cents < 0 && "text-red-700"}>
          {TallyWeb.Money.format(txn.amount_cents)}
        </span>
      </:col>
    </.table>
    <p :if={@transactions_empty?} class="mt-4 text-sm text-zinc-500">
      No transactions yet — import a statement above.
    </p>
    """
  end

  @impl true
  def handle_event("validate-upload", _params, socket), do: {:noreply, socket}

  def handle_event("import", _params, socket) do
    case socket.assigns.uploads.csv.entries do
      [] ->
        {:noreply, put_flash(socket, :error, "Choose a CSV file first")}

      [_entry] ->
        [{filename, content}] =
          consume_uploaded_entries(socket, :csv, fn %{path: path}, entry ->
            {:ok, {entry.client_name, File.read!(path)}}
          end)

        start_import(socket, filename, content)
    end
  end

  @impl true
  def handle_info({:import_completed, import}, socket) do
    {:noreply,
     socket
     |> assign(:active_import, import)
     |> put_flash(import_flash_kind(import), import_flash_message(import))
     |> load_dashboard_data()}
  end

  defp start_import(socket, filename, content) do
    user = socket.assigns.current_user
    account = socket.assigns.account

    with {:ok, import} <- Finance.create_import(user, account, %{filename: filename}),
         {:ok, _job} <- Finance.process_import_async(user, account, import, content) do
      {:noreply,
       socket
       |> assign(:active_import, import)
       |> put_flash(:info, "Importing #{filename}…")}
    else
      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't start the import — try again.")}
    end
  end

  defp load_dashboard_data(socket) do
    account = socket.assigns.account
    today = Date.utc_today()
    from = Date.new!(today.year, today.month, 1)
    to = Date.new!(today.year, today.month, Date.days_in_month(today))
    transactions = Finance.list_transactions(account)

    socket
    |> assign(:balance_cents, Finance.account_balance(account))
    |> assign(:category_breakdown, Finance.spending_by_category(account, from, to))
    |> assign(:monthly_trend, Finance.monthly_totals(account))
    |> assign(:transactions_empty?, transactions == [])
    |> stream(:transactions, transactions, reset: true)
  end

  defp import_flash_kind(%{status: :completed}), do: :info
  defp import_flash_kind(%{status: :failed}), do: :error

  defp import_flash_message(%{status: :completed} = import) do
    "Import finished: #{import.rows_imported} added, #{import.rows_skipped} duplicate(s) skipped, " <>
      "#{import.rows_errored} row(s) had errors."
  end

  defp import_flash_message(%{status: :failed} = import) do
    reason =
      case import.error_details do
        [%{reason: reason} | _] -> reason
        _ -> "unknown reason"
      end

    "Import failed: #{reason}"
  end

  defp category_bar_width(cents, breakdown) do
    max = breakdown |> Enum.map(&elem(&1, 1)) |> Enum.max()
    if max == 0, do: 0, else: round(cents / max * 100)
  end

  defp trend_bar_width(cents, trend) do
    max = trend |> Enum.map(&elem(&1, 1)) |> Enum.max()
    if max == 0, do: 0, else: round(cents / max * 100)
  end

  defp account_type_label(:checking), do: "Checking"
  defp account_type_label(:credit_card), do: "Credit card"

  defp upload_error_message(:too_large), do: "That file is too large (5MB max)."
  defp upload_error_message(:not_accepted), do: "Only .csv files are accepted."
  defp upload_error_message(:too_many_files), do: "Choose one file at a time."
end
