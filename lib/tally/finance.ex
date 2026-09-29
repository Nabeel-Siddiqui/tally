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
  alias Tally.Finance.{Account, CategoryRule, Import, Transaction}
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
    with {int_id, ""} <- Integer.parse(to_string(id)),
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
end
