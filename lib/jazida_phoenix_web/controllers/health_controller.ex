defmodule JazidaPhoenixWeb.HealthController do
  use JazidaPhoenixWeb, :controller

  alias JazidaPhoenix.Mining
  alias JazidaPhoenix.Repo

  def health(conn, _params), do: json(conn, %{status: "ok"})

  def ready(conn, _params) do
    database_ready? = match?({:ok, _result}, Repo.query("SELECT 1"))
    sources = ["sople_stock", "sople_round_results", "sigmine"]

    source_status =
      Map.new(sources, fn source ->
        latest = Mining.latest_import(source)

        {source,
         %{
           fresh: not Mining.stale?(source),
           latest_outcome: latest && latest.status,
           latest_finished_at: latest && latest.finished_at,
           error_summary: latest && latest.error_summary
         }}
      end)

    ready? =
      database_ready? and Enum.all?(source_status, fn {_source, status} -> status.fresh end)

    conn
    |> put_status(if(ready?, do: :ok, else: :service_unavailable))
    |> json(%{
      status: if(ready?, do: "ready", else: "degraded"),
      database: database_ready?,
      sources: source_status
    })
  end
end
