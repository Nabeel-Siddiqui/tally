defmodule Tally.Finance do
  @moduledoc """
  Accounts, their imported transactions, and the category rules a user
  applies to them.

  Every function that reads or writes an `Account` a user doesn't own
  returns `{:error, :not_found}`, not `{:error, :unauthorized}` — a user
  who guesses another user's account id shouldn't be able to tell the
  difference between "not yours" and "doesn't exist."
  """

  import Ecto.Query, warn: false

  alias Tally.Accounts.User
  alias Tally.Finance.{Account, CategoryRule, Import, Importer, ImportWorker, Transaction}
  alias Tally.Repo

  @doc "Creates a financial account owned by `user`."
  @spec create_account(User.t(), map()) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def create_account(%User{} = user, attrs) do
    %Account{user_id: user.id}
    |> Account.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Returns a changeset for tracking `account` form changes, without persisting anything."
  @spec change_account(Account.t(), map()) :: Ecto.Changeset.t()
  def change_account(%Account{} = account, attrs \\ %{}) do
    Account.changeset(account, attrs)
  end

  @doc "Fetches an account by id, scoped to `user`."
  @spec get_account(User.t(), term()) :: {:ok, Account.t()} | {:error, :not_found}
  def get_account(%User{} = user, id) do
    with {:ok, int_id} <- cast_id(id),
         %Account{} = account <- Repo.get_by(Account, id: int_id, user_id: user.id) do
      {:ok, account}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Lists `user`'s accounts, newest first."
  @spec list_accounts(User.t()) :: [Account.t()]
  def list_accounts(%User{} = user) do
    Account
    |> where([a], a.user_id == ^user.id)
    |> order_by([a], desc: a.inserted_at, desc: a.id)
    |> Repo.all()
  end

  @doc "Updates an account, scoped to `user`."
  @spec update_account(User.t(), Account.t(), map()) ::
          {:ok, Account.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def update_account(%User{} = user, %Account{} = account, attrs) do
    with {:ok, account} <- get_account(user, account.id) do
      account
      |> Account.changeset(attrs)
      |> Repo.update()
    end
  end

  @doc "Starts an import record for `account`, scoped to `user`."
  @spec create_import(User.t(), Account.t(), map()) ::
          {:ok, Import.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def create_import(%User{} = user, %Account{} = account, attrs) do
    with {:ok, account} <- get_account(user, account.id) do
      %Import{account_id: account.id}
      |> Import.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc "Fetches an import by id, scoped to `account`."
  @spec get_import(Account.t(), term()) :: {:ok, Import.t()} | {:error, :not_found}
  def get_import(%Account{} = account, id) do
    with {:ok, int_id} <- cast_id(id),
         %Import{} = import <- Repo.get_by(Import, id: int_id, account_id: account.id) do
      {:ok, import}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Parses `csv_content` and writes the result to `import` (already
  created via `create_import/3`): valid rows are bulk-inserted as
  transactions, exact duplicates (by `account_id` + fingerprint, see
  `Transaction`) are silently skipped rather than erroring, and rows
  that didn't parse are counted and recorded on the import itself. The
  insert and the import's final status update happen in one
  transaction, so a result is never left half-written.
  """
  @spec run_import(User.t(), Account.t(), Import.t(), String.t()) ::
          {:ok, Import.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def run_import(%User{} = user, %Account{} = account, %Import{} = import, csv_content)
      when is_binary(csv_content) do
    with {:ok, account} <- get_account(user, account.id) do
      case Importer.process(csv_content, list_category_rules(user)) do
        {:error, :missing_columns} ->
          fail_import(
            account,
            import,
            "CSV is missing a required column: date, description, amount"
          )

        result ->
          insert_and_finalize(account, import, result)
      end
    end
  end

  @doc "Enqueues background processing of `import`'s CSV content via `ImportWorker`."
  @spec process_import_async(User.t(), Account.t(), Import.t(), String.t()) ::
          {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def process_import_async(%User{} = user, %Account{} = account, %Import{} = import, csv_content)
      when is_binary(csv_content) do
    %{user_id: user.id, account_id: account.id, import_id: import.id, csv_content: csv_content}
    |> ImportWorker.new()
    |> Oban.insert()
  end

  @doc """
  Subscribes the caller to `account`'s events — currently just
  `{:import_completed, import}`, broadcast once `run_import/4` finishes
  (success or failure), so a dashboard watching an upload doesn't need
  to poll.
  """
  @spec subscribe_to_account(Account.t()) :: :ok | {:error, term()}
  def subscribe_to_account(%Account{} = account) do
    Phoenix.PubSub.subscribe(Tally.PubSub, account_topic(account))
  end

  defp insert_and_finalize(account, import, result) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(result.transactions, fn transaction ->
        transaction
        |> Map.put(:account_id, account.id)
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    Ecto.Multi.new()
    |> Ecto.Multi.insert_all(:transactions, Transaction, rows,
      on_conflict: :nothing,
      conflict_target: [:account_id, :fingerprint],
      returning: [:id]
    )
    |> Ecto.Multi.update(:import, fn %{transactions: {inserted_count, _}} ->
      Import.status_changeset(import, %{
        status: :completed,
        rows_total: result.rows_total,
        rows_imported: inserted_count,
        rows_skipped: length(result.transactions) - inserted_count,
        rows_errored: result.rows_errored,
        error_details: result.error_details
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{import: import}} ->
        Phoenix.PubSub.broadcast(
          Tally.PubSub,
          account_topic(account),
          {:import_completed, import}
        )

        {:ok, import}

      {:error, :import, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp fail_import(account, import, reason) do
    case import
         |> Import.status_changeset(%{
           status: :failed,
           error_details: [%{row: 0, reason: reason}]
         })
         |> Repo.update() do
      {:ok, import} ->
        Phoenix.PubSub.broadcast(
          Tally.PubSub,
          account_topic(account),
          {:import_completed, import}
        )

        {:ok, import}

      error ->
        error
    end
  end

  defp account_topic(%Account{} = account), do: "account:#{account.id}"

  @doc "Adds a transaction to `account`, scoped to `user`."
  @spec create_transaction(User.t(), Account.t(), map()) ::
          {:ok, Transaction.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def create_transaction(%User{} = user, %Account{} = account, attrs) do
    with {:ok, account} <- get_account(user, account.id) do
      %Transaction{account_id: account.id}
      |> Transaction.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Lists `account`'s transactions, newest first. Takes the account
  itself rather than a user: ownership is enforced once, at whichever
  `get_account/2` call produced this struct in the first place, not
  re-checked on every read that follows it.
  """
  @spec list_transactions(Account.t()) :: [Transaction.t()]
  def list_transactions(%Account{} = account) do
    Transaction
    |> where([t], t.account_id == ^account.id)
    |> order_by([t], desc: t.posted_on, desc: t.id)
    |> Repo.all()
  end

  @doc """
  `account`'s running balance: the sum of every transaction posted to
  it. There's no separate "opening balance" concept — this is exactly
  as accurate as the transaction history imported so far, which is a
  known simplification (see the README).
  """
  @spec account_balance(Account.t()) :: integer()
  def account_balance(%Account{} = account) do
    Transaction
    |> where([t], t.account_id == ^account.id)
    |> select([t], sum(t.amount_cents))
    |> Repo.one()
    |> Kernel.||(0)
  end

  @doc """
  Total spend per category between `from` and `to` (inclusive), most-
  spent first. Spending only — transactions with a positive
  `amount_cents` (credits, refunds) are excluded rather than netted
  against a category, since "how much did I spend on X" is the
  question this answers. A transaction with no assigned category is
  grouped under the literal `"Uncategorized"` rather than dropped, so
  nothing vanishes from the total silently.
  """
  @spec spending_by_category(Account.t(), Date.t(), Date.t()) :: [{String.t(), non_neg_integer()}]
  def spending_by_category(%Account{} = account, %Date{} = from, %Date{} = to) do
    Transaction
    |> where([t], t.account_id == ^account.id)
    |> where([t], t.posted_on >= ^from and t.posted_on <= ^to and t.amount_cents < 0)
    |> select([t], {t.category, t.amount_cents})
    |> Repo.all()
    |> Enum.group_by(fn {category, _amount} -> category || "Uncategorized" end, &elem(&1, 1))
    |> Enum.map(fn {category, amounts} -> {category, -Enum.sum(amounts)} end)
    |> Enum.sort_by(fn {_category, spent_cents} -> -spent_cents end)
  end

  @doc """
  Total spend per calendar month for `account`'s trailing `months`
  months (default 6), oldest first, including months with zero spend —
  a trend chart shouldn't silently skip a quiet month. Same spending-
  only convention as `spending_by_category/3`.
  """
  @spec monthly_totals(Account.t(), pos_integer()) :: [{Date.t(), non_neg_integer()}]
  def monthly_totals(%Account{} = account, months \\ 6) when is_integer(months) and months > 0 do
    today = Date.utc_today()
    current_month = Date.new!(today.year, today.month, 1)
    start_month = shift_months(current_month, -(months - 1))

    spending_by_month =
      Transaction
      |> where([t], t.account_id == ^account.id)
      |> where([t], t.posted_on >= ^start_month and t.amount_cents < 0)
      |> select([t], {t.posted_on, t.amount_cents})
      |> Repo.all()
      |> Enum.group_by(
        fn {posted_on, _amount} -> Date.new!(posted_on.year, posted_on.month, 1) end,
        &elem(&1, 1)
      )
      |> Map.new(fn {month, amounts} -> {month, -Enum.sum(amounts)} end)

    for n <- (months - 1)..0//-1 do
      month = shift_months(current_month, -n)
      {month, Map.get(spending_by_month, month, 0)}
    end
  end

  defp shift_months(%Date{year: year, month: month} = date, offset) do
    zero_indexed_total = year * 12 + (month - 1) + offset
    %{date | year: div(zero_indexed_total, 12), month: rem(zero_indexed_total, 12) + 1}
  end

  @doc "Creates a category rule owned by `user`."
  @spec create_category_rule(User.t(), map()) ::
          {:ok, CategoryRule.t()} | {:error, Ecto.Changeset.t()}
  def create_category_rule(%User{} = user, attrs) do
    %CategoryRule{user_id: user.id}
    |> CategoryRule.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Returns a changeset for tracking `category_rule` form changes, without persisting anything."
  @spec change_category_rule(CategoryRule.t(), map()) :: Ecto.Changeset.t()
  def change_category_rule(%CategoryRule{} = category_rule, attrs \\ %{}) do
    CategoryRule.changeset(category_rule, attrs)
  end

  @doc "Lists `user`'s category rules."
  @spec list_category_rules(User.t()) :: [CategoryRule.t()]
  def list_category_rules(%User{} = user) do
    CategoryRule
    |> where([r], r.user_id == ^user.id)
    |> order_by([r], asc: r.match_text)
    |> Repo.all()
  end

  defp cast_id(id) do
    case Integer.parse(to_string(id)) do
      {int_id, ""} -> {:ok, int_id}
      _ -> :error
    end
  end
end
