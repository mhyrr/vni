defmodule VNIWeb.HealthController do
  @moduledoc """
  Readiness probe for the platform load balancer.

  Deliberately not a LiveView, and deliberately not `/`: the mostly static
  homepage renders fine while every data page is dead. This asks Postgres
  whether it is actually answering.

  The response body says nothing beyond ready/not-ready. A health endpoint is
  a public endpoint, so it never reports build, version, credential, or
  connection detail.
  """
  use VNIWeb, :controller

  require Logger

  @query_timeout_ms 2_000

  def index(conn, _params) do
    if repo_ready?() do
      send_resp(conn, 200, "ok")
    else
      send_resp(conn, 503, "unavailable")
    end
  end

  defp repo_ready? do
    case Ecto.Adapters.SQL.query(VNI.Repo, "SELECT 1", [], timeout: @query_timeout_ms) do
      {:ok, _result} ->
        true

      {:error, reason} ->
        Logger.error("healthz: repo query failed: #{inspect(reason)}")
        false
    end
  rescue
    error ->
      # A checkout timeout or a downed pool raises rather than returning
      # {:error, _}; the probe must answer 503, not crash the request.
      Logger.error("healthz: repo check raised: #{inspect(error)}")
      false
  end
end
