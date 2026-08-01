defmodule JazidaPhoenixWeb.ExplorerLiveTest do
  use JazidaPhoenixWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import JazidaPhoenix.AccountsFixtures
  import JazidaPhoenix.MiningFixtures

  alias JazidaPhoenix.Accounts.Scope
  alias JazidaPhoenix.Notifications

  test "renders stable explorer controls, streams results, filters, and opens details", %{
    conn: conn
  } do
    process = mining_process_fixture(%{municipalities: ["BELÉM"], substances: ["AREIA"]})
    availability_fixture(process)

    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#explorer")
    assert has_element?(view, "#explorer-filter-form")
    assert has_element?(view, "#mining-map[phx-hook='MiningMap'][phx-update='ignore']")
    assert has_element?(view, "#mining-map[data-states-url-template*='servicodados.ibge.gov.br']")
    assert has_element?(view, "#mining-map[data-satellite-tilejson-url*='tiles.example.test']")
    assert has_element?(view, "#map-layers-toggle[aria-controls='map-layers-panel']")
    assert has_element?(view, "#map-layer-mining[checked]")
    assert has_element?(view, "#map-layer-states[checked]")
    assert has_element?(view, "#map-mining-opacity[type='range']")
    assert has_element?(view, "#basemap-satellite")
    assert has_element?(view, "#process-results a[href*='process=#{process.id}']")

    view
    |> form("#explorer-filter-form", filters: %{q: "inexistente"})
    |> render_change()

    assert_patch(view, "/?q=inexistente")
    assert has_element?(view, "#results-empty")

    {:ok, selected_view, _html} = live(conn, ~p"/?process=#{process.id}")
    assert has_element?(selected_view, "#process-detail")
    assert has_element?(selected_view, "#watch-process")
    assert has_element?(selected_view, "a[title='Abrir fonte oficial ANM']")
  end

  test "anonymous watch action routes to login", %{conn: conn} do
    process = mining_process_fixture()
    availability_fixture(process)
    {:ok, view, _html} = live(conn, ~p"/?process=#{process.id}")

    view |> element("#watch-process") |> render_click()
    assert_redirect(view, ~p"/users/log-in")
  end

  test "authenticated users can watch and unwatch from the detail drawer", %{conn: conn} do
    user = unconfirmed_user_fixture()
    process = mining_process_fixture()
    availability_fixture(process)
    conn = log_in_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/?process=#{process.id}")

    view |> element("#watch-process") |> render_click()
    assert has_element?(view, "#unwatch-process")
    assert Notifications.watched?(Scope.for_user(user), process.id)

    view |> element("#unwatch-process") |> render_click()
    assert has_element?(view, "#watch-process")
    refute Notifications.watched?(Scope.for_user(user), process.id)
  end
end
