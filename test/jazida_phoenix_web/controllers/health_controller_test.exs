defmodule JazidaPhoenixWeb.HealthControllerTest do
  use JazidaPhoenixWeb.ConnCase, async: true

  alias JazidaPhoenix.Mining.SourceImport
  alias JazidaPhoenix.Repo

  test "distinguishes process health from source readiness", %{conn: conn} do
    Repo.delete_all(SourceImport)
    assert %{"status" => "ok"} = json_response(get(conn, "/health"), 200)

    response = conn |> recycle() |> get("/ready") |> json_response(503)
    assert response["status"] == "degraded"
    assert response["database"]
    refute response["sources"]["sigmine"]["fresh"]
    assert is_nil(response["sources"]["sigmine"]["latest_outcome"])
  end
end
