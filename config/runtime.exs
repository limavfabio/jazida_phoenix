import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/jazida_phoenix start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :jazida_phoenix, JazidaPhoenixWeb.Endpoint, server: true
end

config :jazida_phoenix, JazidaPhoenixWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

mining_config = Application.fetch_env!(:jazida_phoenix, :mining)

config :jazida_phoenix,
       :mining,
       Keyword.merge(mining_config,
         map_style_url: System.get_env("MAP_STYLE_URL", mining_config[:map_style_url]),
         satellite_tilejson_url:
           System.get_env("SATELLITE_TILEJSON_URL", mining_config[:satellite_tilejson_url]),
         states_geojson_url_template:
           System.get_env(
             "STATES_GEOJSON_URL_TEMPLATE",
             mining_config[:states_geojson_url_template]
           ),
         sople_stock_url: System.get_env("SOPLE_STOCK_URL", mining_config[:sople_stock_url]),
         sople_round_results_url:
           System.get_env("SOPLE_ROUND_RESULTS_URL", mining_config[:sople_round_results_url]),
         sigmine_active_url:
           System.get_env("SIGMINE_ACTIVE_URL", mining_config[:sigmine_active_url]),
         sigmine_inactive_url:
           System.get_env("SIGMINE_INACTIVE_URL", mining_config[:sigmine_inactive_url]),
         stale_after_hours:
           String.to_integer(
             System.get_env(
               "SOURCE_STALE_AFTER_HOURS",
               to_string(mining_config[:stale_after_hours])
             )
           )
       )

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :jazida_phoenix, JazidaPhoenixWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
        # Gettext translations
        ~r"priv/gettext/.*\.po$",
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/jazida_phoenix_web/router\.ex$",
        ~r"lib/jazida_phoenix_web/(controllers|live|components)/.*\.(ex|heex)$"
      ]
    ]
end

if config_env() == :prod do
  map_style_url =
    System.get_env("MAP_STYLE_URL") ||
      raise "MAP_STYLE_URL is required in production (use an HTTPS MapLibre style URL)"

  unless URI.parse(map_style_url).scheme == "https" do
    raise "MAP_STYLE_URL must use HTTPS in production"
  end

  if satellite_tilejson_url = System.get_env("SATELLITE_TILEJSON_URL") do
    unless URI.parse(satellite_tilejson_url).scheme == "https" do
      raise "SATELLITE_TILEJSON_URL must use HTTPS in production"
    end
  end

  if is_nil(System.find_executable("ogr2ogr")) do
    raise "ogr2ogr is required in production for SIGMINE synchronization"
  end

  resend_api_key =
    System.get_env("RESEND_API_KEY") ||
      raise "RESEND_API_KEY is required in production for account and digest email"

  email_from =
    System.get_env("EMAIL_FROM") ||
      raise "EMAIL_FROM is required in production (for example, notificacoes@example.com)"

  config :jazida_phoenix, JazidaPhoenix.Mailer,
    adapter: Swoosh.Adapters.Resend,
    api_key: resend_api_key

  config :jazida_phoenix, :email_from, {"Jazida", email_from}

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :jazida_phoenix, JazidaPhoenix.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6,
    types: JazidaPhoenix.PostgresTypes

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :jazida_phoenix, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :jazida_phoenix, JazidaPhoenixWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :jazida_phoenix, JazidaPhoenixWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :jazida_phoenix, JazidaPhoenixWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :jazida_phoenix, JazidaPhoenix.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://swoosh.hexdocs.pm/Swoosh.html#module-installation for details.
end
