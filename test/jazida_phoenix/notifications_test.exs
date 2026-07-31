defmodule JazidaPhoenix.NotificationsTest do
  use JazidaPhoenix.DataCase, async: false

  import JazidaPhoenix.AccountsFixtures
  import JazidaPhoenix.MiningFixtures
  import Swoosh.TestAssertions

  alias JazidaPhoenix.Accounts.Scope
  alias JazidaPhoenix.Notifications
  alias JazidaPhoenix.Notifications.{Digest, Notification}

  test "scopes watches and notifications to their owner and deduplicates materialization" do
    owner = unconfirmed_user_fixture()
    other = unconfirmed_user_fixture()
    owner_scope = Scope.for_user(owner)
    process = mining_process_fixture()
    source_import = source_import_fixture()
    change = process_change_fixture(process, source_import)

    assert {:ok, _watch} = Notifications.watch(owner_scope, process.id)
    assert Notifications.watched?(owner_scope, process.id)
    refute Notifications.watched?(Scope.for_user(other), process.id)

    assert {1, _} = Notifications.materialize(source_import.id)
    assert {0, _} = Notifications.materialize(source_import.id)
    assert [notification] = Notifications.list_notifications(owner_scope)
    assert notification.process_change.id == change.id
    assert Notifications.list_notifications(Scope.for_user(other)) == []
    assert {:error, :not_found} = Notifications.mark_read(Scope.for_user(other), notification.id)
    assert :ok = Notifications.mark_read(owner_scope, notification.id)
    assert [%{read_at: %DateTime{}}] = Notifications.list_notifications(owner_scope)

    assert :ok = Notifications.unwatch(Scope.for_user(other), process.id)
    assert Notifications.watched?(owner_scope, process.id)
    assert :ok = Notifications.unwatch(owner_scope, process.id)
    refute Notifications.watched?(owner_scope, process.id)
  end

  test "delivers one Brasília-day digest and marks delivery only after adapter acceptance" do
    user = unconfirmed_user_fixture()
    scope = Scope.for_user(user)
    process = mining_process_fixture()
    source_import = source_import_fixture()
    _change = process_change_fixture(process, source_import)
    {:ok, _watch} = Notifications.watch(scope, process.id)
    {1, _} = Notifications.materialize(source_import.id)

    assert Notifications.brasilia_date(~U[2026-07-30 02:59:59Z]) == ~D[2026-07-29]
    assert Notifications.brasilia_date(~U[2026-07-30 03:00:00Z]) == ~D[2026-07-30]

    now = ~U[2026-07-30 12:00:00Z]
    assert :ok = Notifications.deliver_daily_digests(now)

    assert_email_sent(fn email ->
      assert email.subject == "Alterações nas áreas que você acompanha"
      assert email.text_body =~ process.process_number
      assert email.text_body =~ "/notificacoes"
    end)

    assert %Notification{delivered_at: %DateTime{}, digest_date: ~D[2026-07-30]} =
             Repo.one!(Notification)

    assert %Digest{status: "sent", notification_count: 1} = Repo.one!(Digest)

    assert :ok = Notifications.deliver_daily_digests(now)
    refute_email_sent()
  end
end
