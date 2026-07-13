# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :vni,
  namespace: VNI,
  ecto_repos: [VNI.Repo],
  generators: [timestamp_type: :utc_datetime]

# PostGIS geometry types (see lib/vni/postgres_types.ex)
config :vni, VNI.Repo, types: VNI.PostgresTypes

config :geo_postgis, json_library: Jason

# Oban job processing. Queues stay minimal until the Pledge phase
# adds evaluation + outreach work.
config :vni, Oban,
  engine: Oban.Engines.Basic,
  repo: VNI.Repo,
  plugins: [{Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7}],
  queues: [default: 10, ingest: 2]

# Configures the endpoint
config :vni, VNIWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: VNIWeb.ErrorHTML, json: VNIWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: VNI.PubSub,
  live_view: [signing_salt: "cY13BDo1"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :vni, VNI.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  vni: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  vni: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
