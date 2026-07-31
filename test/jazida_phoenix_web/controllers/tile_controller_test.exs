defmodule JazidaPhoenixWeb.TileControllerTest do
  use JazidaPhoenixWeb.ConnCase, async: true

  import JazidaPhoenix.MiningFixtures

  test "returns valid polygon and cluster MVT responses with cache boundaries", %{conn: conn} do
    geometry = %Geo.MultiPolygon{
      coordinates: [[[{-36.2, -9.2}, {-36.1, -9.2}, {-36.1, -9.1}, {-36.2, -9.1}, {-36.2, -9.2}]]],
      srid: 4674
    }

    process = mining_process_fixture(%{geometry: geometry, state_code: "AL"})
    availability_fixture(process)

    polygon_conn = get(conn, "/tiles/8/102/134")
    assert response(polygon_conn, 200) != <<>>

    assert get_resp_header(polygon_conn, "content-type") == [
             "application/vnd.mapbox-vector-tile; charset=utf-8"
           ]

    assert get_resp_header(polygon_conn, "cache-control") == [
             "public, max-age=300, stale-while-revalidate=600"
           ]

    cluster_conn = get(recycle(conn), "/tiles/4/6/8")
    assert response(cluster_conn, 200) != <<>>
  end

  test "returns an empty successful tile and rejects invalid coordinates", %{conn: conn} do
    assert response(get(conn, "/tiles/8/0/0"), 200) == <<>>
    assert response(get(recycle(conn), "/tiles/15/0/0"), 404) == "not found"
    assert response(get(recycle(conn), "/tiles/8/256/0"), 404) == "not found"
    assert response(get(recycle(conn), "/tiles/not-a-number/0/0"), 404) == "not found"
  end
end
