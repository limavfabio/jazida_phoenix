defmodule JazidaPhoenix.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      JazidaPhoenixWeb.Telemetry,
      JazidaPhoenix.Repo,
      {DNSCluster, query: Application.get_env(:jazida_phoenix, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: JazidaPhoenix.PubSub},
      # Start a worker by calling: JazidaPhoenix.Worker.start_link(arg)
      # {JazidaPhoenix.Worker, arg},
      # Start to serve requests, typically the last entry
      JazidaPhoenixWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: JazidaPhoenix.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    JazidaPhoenixWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
