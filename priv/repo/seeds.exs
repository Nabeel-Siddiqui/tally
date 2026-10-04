# Populates a demo user with two accounts, a few category rules, and six
# months of realistic transactions, so a fresh clone or a public demo
# deployment has something to look at immediately.
#
#     mix run priv/repo/seeds.exs
#
# The transactions go through the real CSV import pipeline
# (Finance.create_import/3 + Finance.run_import/4), not direct inserts,
# so the demo data exercises the same path a user's upload would.
#
# Safe to run more than once: it does nothing if the demo user already
# has an account.

alias Tally.Accounts
alias Tally.Accounts.User
alias Tally.Finance
alias Tally.Repo

demo_email = "demo@tally.dev"
demo_password = "demo-password-please-change"

user =
  case Repo.get_by(User, email: demo_email) do
    nil ->
      {:ok, user} = Accounts.register_user(%{email: demo_email, password: demo_password})
      user

    existing ->
      existing
  end

if Finance.list_accounts(user) == [] do
  {:ok, checking} = Finance.create_account(user, %{name: "Everyday Checking", type: :checking})
  {:ok, card} = Finance.create_account(user, %{name: "Rewards Card", type: :credit_card})

  for {match_text, category} <- [
        {"NETFLIX", "Subscriptions"},
        {"SPOTIFY", "Subscriptions"},
        {"WHOLE FOODS", "Groceries"},
        {"TRADER JOE", "Groceries"},
        {"SHELL", "Transport"},
        {"UBER", "Transport"},
        {"STARBUCKS", "Dining"}
      ] do
    {:ok, _rule} =
      Finance.create_category_rule(user, %{match_text: match_text, category: category})
  end

  format_cents = fn cents ->
    sign = if cents < 0, do: "-", else: ""
    magnitude = abs(cents)

    "#{sign}#{div(magnitude, 100)}.#{magnitude |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  today = Date.utc_today()

  # Each month's rows, as {day_of_month, description, amount_cents}.
  # Days stay at or below 28 so every month has them.
  month_rows = fn ->
    [
      {1, "RENT PAYMENT", -180_000},
      {1, "NETFLIX.COM 8829", -1599},
      {3, "SPOTIFY USA 1200", -1099},
      {5, "WHOLE FOODS MKT 0412", -8742},
      {9, "SHELL OIL 57442", -5210},
      {11, "STARBUCKS STORE 3321", -684},
      {12, "TRADER JOE'S 221", -6315},
      {14, "UBER TRIP 8821", -1876},
      {15, "ACME PAYROLL", 285_000},
      {19, "STARBUCKS STORE 3321", -722},
      {22, "WHOLE FOODS MKT 0412", -9125},
      {26, "ELECTRIC COMPANY", -11_230}
    ]
  end

  # Six calendar months back to and including this one, with the first
  # of each month as its anchor date.
  months =
    for offset <- 5..0//-1 do
      total = today.year * 12 + (today.month - 1) - offset
      Date.new!(div(total, 12), rem(total, 12) + 1, 1)
    end

  rows =
    for month_start <- months, {day, description, cents} <- month_rows.() do
      posted_on = Date.new!(month_start.year, month_start.month, day)
      "#{Date.to_iso8601(posted_on)},#{description},#{format_cents.(cents)}"
    end

  csv = Enum.join(["date,description,amount" | rows], "\n") <> "\n"

  card_rows =
    for month_start <- months do
      posted_on = Date.new!(month_start.year, month_start.month, 20)
      "#{Date.to_iso8601(posted_on)},AMAZON MKTPLACE PMTS,-#{format_cents.(4599)}"
    end

  card_csv = Enum.join(["date,description,amount" | card_rows], "\n") <> "\n"

  for {account, body} <- [{checking, csv}, {card, card_csv}] do
    {:ok, import} = Finance.create_import(user, account, %{filename: "seed-#{account.type}.csv"})
    {:ok, _import} = Finance.run_import(user, account, import, body)
  end
end

IO.puts("""

Seeded demo user:
  email:    #{demo_email}
  password: #{demo_password}
""")
