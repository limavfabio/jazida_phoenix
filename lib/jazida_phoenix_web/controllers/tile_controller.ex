defmodule JazidaPhoenixWeb.TileController do
  use JazidaPhoenixWeb, :controller

  alias JazidaPhoenix.Mining.Tiles

  def show(conn, %{"z" => z, "x" => x, "y" => y}) do
    with {z, ""} <- Integer.parse(z),
         {x, ""} <- Integer.parse(x),
         {y, ""} <- Integer.parse(y),
         {:ok, tile} <- Tiles.fetch(z, x, y) do
      conn
      |> put_resp_content_type("application/vnd.mapbox-vector-tile")
      |> put_resp_header("cache-control", "public, max-age=300, stale-while-revalidate=600")
      |> send_resp(200, tile)
    else
      _ -> send_resp(conn, 404, "not found")
    end
  end
end
