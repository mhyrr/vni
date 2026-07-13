import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :vni, VNI.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "vni_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Run Oban inline assertions only — no background processing in tests
config :vni, Oban, testing: :manual

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :vni, VNIWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "TZJjnFvsGQ9q1sufLMVJBCcbSGT1X627dWfdXIjimJ58TjmGq+WyUsl2SWMDUSC7",
  server: false

# In test we don't send emails
config :vni, VNI.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
