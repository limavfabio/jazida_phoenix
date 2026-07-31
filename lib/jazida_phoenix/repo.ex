defmodule JazidaPhoenix.Repo do
  use Ecto.Repo,
    otp_app: :jazida_phoenix,
    adapter: Ecto.Adapters.Postgres
end

Postgrex.Types.define(
  JazidaPhoenix.PostgresTypes,
  [Geo.PostGIS.Extension] ++ Ecto.Adapters.Postgres.extensions(),
  json: Jason
)
