# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :jazida_phoenix, :scopes,
  user: [
    default: true,
    module: JazidaPhoenix.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: JazidaPhoenix.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :jazida_phoenix,
  ecto_repos: [JazidaPhoenix.Repo],
  generators: [timestamp_type: :utc_datetime]

config :jazida_phoenix, JazidaPhoenix.Repo, types: JazidaPhoenix.PostgresTypes

config :jazida_phoenix, Oban,
  repo: JazidaPhoenix.Repo,
  queues: [imports: 1, notifications: 5],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 7 * 24 * 60 * 60},
    {Oban.Plugins.Cron,
     crontab: [
       {"17 5 * * *", JazidaPhoenix.Mining.Workers.SopleSyncWorker},
       {"47 5 * * *", JazidaPhoenix.Mining.Workers.SigmineSyncWorker},
       {"0 11 * * *", JazidaPhoenix.Notifications.DigestWorker}
     ]}
  ]

config :jazida_phoenix, :mining,
  timezone: "America/Sao_Paulo",
  map_style_url: "https://demotiles.maplibre.org/style.json",
  states_geojson_url_template:
    "https://servicodados.ibge.gov.br/api/v3/malhas/estados/{state}?formato=application/vnd.geo+json&qualidade=minima",
  stale_after_hours: 48,
  sople_stock_url: "https://dadosabertos.anm.gov.br/SOPLE/EstoqueAreas.csv",
  sople_round_results_url:
    "https://dadosabertos.anm.gov.br/SOPLE/ResultadoRodadaDisponibilidade.csv",
  sigmine_active_url: "https://dadosabertos.anm.gov.br/SIGMINE/PROCESSOS_MINERARIOS/BRASIL.zip",
  sigmine_inactive_url:
    "https://dadosabertos.anm.gov.br/SIGMINE/PROCESSOS_MINERARIOS/PROCESSOS_INATIVOS.zip",
  download_timeout_ms: 120_000,
  max_download_bytes: 2_000_000_000,
  max_archive_entries: 32,
  max_archive_uncompressed_bytes: 5_000_000_000

# Configure the endpoint
config :jazida_phoenix, JazidaPhoenixWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: JazidaPhoenixWeb.ErrorHTML, json: JazidaPhoenixWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: JazidaPhoenix.PubSub,
  live_view: [signing_salt: "VWzELXOg"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :jazida_phoenix, JazidaPhoenix.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  jazida_phoenix: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  jazida_phoenix: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    :source,
    :source_import_id,
    :outcome,
    :duration_ms,
    :parsed_rows,
    :imported_rows,
    :warning_count
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
