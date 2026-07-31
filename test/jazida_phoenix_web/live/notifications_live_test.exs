defmodule JazidaPhoenixWeb.NotificationsLiveTest do
  use JazidaPhoenixWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import JazidaPhoenix.AccountsFixtures
  import JazidaPhoenix.MiningFixtures

  alias JazidaPhoenix.Accounts.Scope
  alias JazidaPhoenix.Notifications

  test "requires authentication", %{conn: conn} do
    assert {:error, redirect} = live(conn, ~p"/notificacoes")
    assert {:redirect, %{to: "/users/log-in"}} = redirect
  end

  test "streams only the current user's notifications and marks them read", %{conn: conn} do
    user = unconfirmed_user_fixture()
    process = mining_process_fixture()
    source_import = source_import_fixture()
    _change = process_change_fixture(process, source_import)
    {:ok, _watch} = Notifications.watch(Scope.for_user(user), process.id)
    {1, _} = Notifications.materialize(source_import.id)
    [notification] = Notifications.list_notifications(Scope.for_user(user))

    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/notificacoes")
    assert has_element?(view, "#notifications")
    assert has_element?(view, "#mark-read-#{notification.id}")

    view |> element("#mark-read-#{notification.id}") |> render_click()
    refute has_element?(view, "#mark-read-#{notification.id}")
  end
end
