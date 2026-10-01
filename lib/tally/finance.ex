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
          fail_import(import, "CSV is missing a required column: date, description, amount")

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
      {:ok, %{import: import}} -> {:ok, import}
      {:error, :import, changeset, _changes} -> {:error, changeset}
    end
  end

  defp fail_import(import, reason) do
    import
    |> Import.status_changeset(%{status: :failed, error_details: [%{row: 0, reason: reason}]})
    |> Repo.update()
  end

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

  @doc "Creates a category rule owned by `user`."
  @spec create_category_rule(User.t(), map()) ::
          {:ok, CategoryRule.t()} | {:error, Ecto.Changeset.t()}
  def create_category_rule(%User{} = user, attrs) do
    %CategoryRule{user_id: user.id}
    |> CategoryRule.changeset(attrs)
    |> Repo.insert()
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
