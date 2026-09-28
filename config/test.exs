import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :tally, Tally.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "tally_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :tally, TallyWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "xtlR4xaVV1t1cXQedmCwhzeD2B5tZo4mLX0YVqB3sJK6sujnSWWJ8Gcdi0r3ohZ0",
  server: false

# In test we don't send emails
config :tally, Tally.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Oban.Testing's :manual mode — jobs are inserted into the database (so
# uniqueness/argument assertions still work) but never picked up by a
# real queue. Tests trigger perform/1 explicitly via Oban.Testing.
config :tally, Oban, testing: :manual

# Lets Phoenix.Ecto.SQL.Sandbox (wired into the endpoint) share a test's
# sandbox connection with the separate process a LiveView test spawns
# for the "connected" mount — without it, any DB call from inside a
# LiveView's handle_event/handle_info raises DBConnection.OwnershipError,
# since :manual-mode sandbox ownership doesn't cross processes on its
# own. (A real gap found the hard way on a previous project — wiring it
# up from day one here instead.)
config :tally, sql_sandbox: true
