defmodule VNI.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      VNIWeb.Telemetry,
      VNI.Repo,
      {Oban, Application.fetch_env!(:vni, Oban)},
      {DNSCluster, query: Application.get_env(:vni, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: VNI.PubSub},
      # Start a worker by calling: VNI.Worker.start_link(arg)
      # {VNI.Worker, arg},
      # Start to serve requests, typically the last entry
      VNIWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: VNI.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    VNIWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
