defmodule JazidaPhoenix.Mining.Tiles do
  @moduledoc "Indexed PostGIS vector-tile queries for the public explorer."

  alias JazidaPhoenix.Repo

  @min_zoom 0
  @max_zoom 14
  @polygon_zoom 7

  def fetch(z, x, y) when is_integer(z) and is_integer(x) and is_integer(y) do
    with :ok <- validate(z, x, y) do
      sql = if z < @polygon_zoom, do: cluster_sql(), else: polygon_sql()
      %{rows: [[tile]]} = Repo.query!(sql, [z, x, y])
      {:ok, tile || <<>>}
    end
  end

  def fetch(_z, _x, _y), do: {:error, :invalid_tile}

  def validate(z, x, y) when z in @min_zoom..@max_zoom do
    edge = Integer.pow(2, z)
    if x in 0..(edge - 1) and y in 0..(edge - 1), do: :ok, else: {:error, :invalid_tile}
  end

  def validate(_z, _x, _y), do: {:error, :invalid_tile}

  defp polygon_sql do
    """
    WITH bounds AS (SELECT ST_TileEnvelope($1, $2, $3) AS geom),
    features AS (
      SELECT p.id,
             p.process_number,
             p.state_code,
             p.area_ha,
             p.substances[1] AS primary_substance,
             a.display_category AS category,
             a.availability_regime,
             ST_AsMVTGeom(ST_Transform(p.geometry, 3857), bounds.geom, 4096, 64, true) AS geom
      FROM mining_processes p
      CROSS JOIN bounds
      LEFT JOIN area_availabilities a ON a.mining_process_id = p.id
      WHERE p.geometry IS NOT NULL
        AND p.geometry && ST_Transform(bounds.geom, 4674)
    )
    SELECT ST_AsMVT(features, 'areas', 4096, 'geom') FROM features
    """
  end

  defp cluster_sql do
    """
    WITH bounds AS (SELECT ST_TileEnvelope($1, $2, $3) AS geom),
    points AS (
      SELECT ST_SnapToGrid(
               ST_Transform(ST_PointOnSurface(p.geometry), 3857),
               40075016.68557849 / power(2, $1) / 8
             ) AS point,
             coalesce(a.display_category, 'unknown') AS category
      FROM mining_processes p
      CROSS JOIN bounds
      LEFT JOIN area_availabilities a ON a.mining_process_id = p.id
      WHERE p.geometry IS NOT NULL
        AND p.geometry && ST_Transform(bounds.geom, 4674)
    ), clusters AS (
      SELECT count(*)::integer AS count,
             category,
             ST_AsMVTGeom(point, bounds.geom, 4096, 64, true) AS geom
      FROM points
      CROSS JOIN bounds
      GROUP BY point, category, bounds.geom
    )
    SELECT ST_AsMVT(clusters, 'areas', 4096, 'geom') FROM clusters
    """
  end
end
