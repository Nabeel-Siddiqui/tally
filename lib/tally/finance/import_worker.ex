defmodule Tally.Finance.ImportWorker do
  @moduledoc """
  Runs an already-created import's CSV content in the background via
  `Finance.run_import/4`. The CSV content is carried in the job's own
  args rather than written to a file somewhere and referenced by path —
  bank statement CSVs are small (at most a few thousand rows) and this
  is a one-shot, short-lived payload, so storing it alongside the job
  avoids standing up separate file storage for something Oban's own
  `args` column already handles fine.
  """

  use Oban.Worker, queue: :imports, max_attempts: 3

  alias Tally.Accounts
  alias Tally.Finance

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "user_id" => user_id,
          "account_id" => account_id,
          "import_id" => import_id,
          "csv_content" => csv_content
        }
      }) do
    user = Accounts.get_user!(user_id)

    with {:ok, account} <- Finance.get_account(user, account_id),
         {:ok, import} <- Finance.get_import(account, import_id),
         {:ok, _import} <- Finance.run_import(user, account, import, csv_content) do
      :ok
    end
  end
end
