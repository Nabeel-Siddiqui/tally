defmodule Tally.Finance.ImportWorkerTest do
  use Tally.DataCase, async: true
  use Oban.Testing, repo: Tally.Repo

  import Tally.AccountsFixtures
  import Tally.FinanceFixtures

  alias Tally.Finance
  alias Tally.Finance.ImportWorker

  test "runs the import and leaves it completed" do
    user = user_fixture()
    account = account_fixture(%{}, user)
    {:ok, import} = Finance.create_import(user, account, %{filename: "jan.csv"})

    csv = "date,description,amount\n2026-01-15,Coffee,-4.50\n"

    assert :ok =
             perform_job(ImportWorker, %{
               "user_id" => user.id,
               "account_id" => account.id,
               "import_id" => import.id,
               "csv_content" => csv
             })

    assert {:ok, updated} = Finance.get_import(account, import.id)
    assert updated.status == :completed
    assert updated.rows_imported == 1
  end

  test "enqueuing via process_import_async/4 and performing it end to end works" do
    user = user_fixture()
    account = account_fixture(%{}, user)
    {:ok, import} = Finance.create_import(user, account, %{filename: "jan.csv"})

    assert {:ok, _job} =
             Finance.process_import_async(
               user,
               account,
               import,
               "date,description,amount\n2026-01-15,Coffee,-4.50\n"
             )

    assert_enqueued(worker: ImportWorker)
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :imports)

    assert {:ok, updated} = Finance.get_import(account, import.id)
    assert updated.status == :completed
  end
end
