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
#     PHX_SERVER=true bin/vni start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :vni, VNIWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :vni, VNI.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

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
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :vni, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :vni, VNIWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :vni, VNIWeb.Endpoint,
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
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :vni, VNIWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## The mailer
  #
  # Resend, through Swoosh's adapter. The API client is set in
  # config/prod.exs (Swoosh.ApiClient.Req — CLAUDE.md's HTTP rule).
  #
  # A missing key raises at boot rather than degrading quietly. Every
  # commitment is double opt-in: with no way to send, nobody can ever be
  # counted, and the failure would show up as a number that never moves
  # rather than as an error anyone sees.
  # Blank, not just unset: `fly secrets set RESEND_API_KEY=` leaves an
  # empty string, which is perfectly truthy and would sail through an
  # `||` check straight into a failing send.
  resend_api_key =
    case System.get_env("RESEND_API_KEY") do
      key when is_binary(key) and key != "" ->
        key

      _blank ->
        raise """
        environment variable RESEND_API_KEY is missing or empty.

        Every commitment is confirmed by email, so without it no pledge
        can ever be counted. Set it with:

            fly secrets set RESEND_API_KEY=re_...
        """
    end

  config :vni, VNI.Mailer,
    adapter: Swoosh.Adapters.Resend,
    api_key: resend_api_key

  # Resend refuses any address outside a domain verified in the account,
  # so MAIL_FROM has to match one. Overridable without a deploy.
  config :vni, VNI.Pledges.Notifier,
    from: {
      System.get_env("MAIL_FROM_NAME") || "Vote No Incumbents",
      System.get_env("MAIL_FROM") || "commitments@voteno.org"
    }
end

# Real sends from the development machine, opt-in per shell. Without the
# key set, dev keeps the Local adapter and its mailbox at /dev/mailbox —
# so this can never surprise anyone into mailing a live address.
if config_env() == :dev do
  case System.get_env("RESEND_API_KEY") do
    resend_api_key when is_binary(resend_api_key) and resend_api_key != "" ->
      config :vni, VNI.Mailer,
        adapter: Swoosh.Adapters.Resend,
        api_key: resend_api_key

      config :swoosh, :api_client, Swoosh.ApiClient.Req

      case System.get_env("MAIL_FROM") do
        from when is_binary(from) and from != "" ->
          config :vni, VNI.Pledges.Notifier,
            from: {System.get_env("MAIL_FROM_NAME") || "Vote No Incumbents", from}

        _blank ->
          :ok
      end

    _blank ->
      :ok
  end
end
