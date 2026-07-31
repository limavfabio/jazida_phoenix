defmodule JazidaPhoenix.Notifications do
  @moduledoc "User-scoped watches, change notifications, and digest delivery."

  import Ecto.Query

  alias JazidaPhoenix.Accounts.Scope
  alias JazidaPhoenix.Mailer
  alias JazidaPhoenix.Mining.ProcessChange
  alias JazidaPhoenix.Notifications.{Digest, Notification, Watch}
  alias JazidaPhoenix.Repo
  alias Swoosh.Email

  def watch(%Scope{user: user}, mining_process_id) when is_integer(mining_process_id) do
    now = DateTime.utc_now(:second)

    Repo.insert_all(
      Watch,
      [
        %{
          user_id: user.id,
          mining_process_id: mining_process_id,
          active: true,
          inserted_at: now,
          updated_at: now
        }
      ],
      conflict_target: [:user_id, :mining_process_id],
      on_conflict: {:replace, [:active, :updated_at]}
    )

    get_watch(user.id, mining_process_id)
  end

  def watch(_scope, _mining_process_id), do: {:error, :unauthorized}

  def unwatch(%Scope{user: user}, mining_process_id) when is_integer(mining_process_id) do
    Watch
    |> where([watch], watch.user_id == ^user.id and watch.mining_process_id == ^mining_process_id)
    |> Repo.update_all(set: [active: false, updated_at: DateTime.utc_now(:second)])

    :ok
  end

  def unwatch(_scope, _mining_process_id), do: {:error, :unauthorized}

  def watched?(%Scope{user: user}, mining_process_id) do
    Repo.exists?(
      from watch in Watch,
        where:
          watch.user_id == ^user.id and watch.mining_process_id == ^mining_process_id and
            watch.active
    )
  end

  def watched?(_scope, _mining_process_id), do: false

  def list_notifications(scope, opts \\ [])

  def list_notifications(%Scope{user: user}, opts) do
    limit = opts |> Keyword.get(:limit, 100) |> min(100) |> max(1)

    Notification
    |> where([notification], notification.user_id == ^user.id)
    |> order_by([notification], desc: notification.inserted_at)
    |> limit(^limit)
    |> preload([:mining_process, :process_change])
    |> Repo.all()
  end

  def list_notifications(_scope, _opts), do: []

  def mark_read(%Scope{user: user}, notification_id) do
    Notification
    |> where(
      [notification],
      notification.id == ^notification_id and notification.user_id == ^user.id
    )
    |> Repo.update_all(set: [read_at: DateTime.utc_now(:second)])
    |> case do
      {1, _} -> :ok
      _ -> {:error, :not_found}
    end
  end

  def mark_read(_scope, _notification_id), do: {:error, :unauthorized}

  def materialize(source_import_id) do
    now = DateTime.utc_now(:second)

    rows =
      ProcessChange
      |> join(:inner, [change], watch in Watch,
        on: watch.mining_process_id == change.mining_process_id and watch.active
      )
      |> where([change], change.source_import_id == ^source_import_id)
      |> select([change, watch], %{
        user_id: watch.user_id,
        mining_process_id: change.mining_process_id,
        process_change_id: change.id
      })
      |> Repo.all()
      |> Enum.map(&Map.merge(&1, %{inserted_at: now, updated_at: now}))

    rows
    |> Enum.chunk_every(2_000)
    |> Enum.reduce({0, nil}, fn chunk, {count, _last} ->
      {inserted, result} = Repo.insert_all(Notification, chunk, on_conflict: :nothing)
      {count + inserted, result}
    end)
  end

  def deliver_daily_digests(now \\ DateTime.utc_now()) do
    date = brasilia_date(now)

    results = pending_users(date) |> Enum.map(&deliver_user_digest(&1, date, now))
    if Enum.all?(results, &match?({:ok, _}, &1)), do: :ok, else: {:error, results}
  end

  def brasilia_date(%DateTime{} = datetime),
    do: datetime |> DateTime.add(-3 * 60 * 60, :second) |> DateTime.to_date()

  defp deliver_user_digest(user, date, now) do
    digest = get_or_create_digest(user.id, date)

    if digest.status == "sent" do
      {:ok, digest}
    else
      notifications = pending_notifications(user.id, date)

      if notifications == [] do
        {:ok, digest}
      else
        email = digest_email(user.email, notifications)

        with {:ok, _metadata} <- Mailer.deliver(email),
             {:ok, sent} <- mark_digest_sent(digest, notifications, date, now) do
          {:ok, sent}
        else
          {:error, reason} -> mark_digest_failed(digest, reason)
        end
      end
    end
  end

  defp pending_users(date) do
    JazidaPhoenix.Accounts.User
    |> join(:inner, [user], notification in Notification, on: notification.user_id == user.id)
    |> where(
      [_user, notification],
      is_nil(notification.delivered_at) and
        (is_nil(notification.digest_date) or notification.digest_date == ^date)
    )
    |> distinct(true)
    |> Repo.all()
  end

  defp pending_notifications(user_id, date) do
    Notification
    |> where(
      [notification],
      notification.user_id == ^user_id and is_nil(notification.delivered_at) and
        (is_nil(notification.digest_date) or notification.digest_date == ^date)
    )
    |> order_by([notification], asc: notification.inserted_at)
    |> preload([:mining_process, :process_change])
    |> Repo.all()
  end

  defp get_or_create_digest(user_id, date) do
    now = DateTime.utc_now(:second)

    Repo.insert_all(
      Digest,
      [
        %{
          user_id: user_id,
          calendar_date: date,
          status: "pending",
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:user_id, :calendar_date]
    )

    Repo.get_by!(Digest, user_id: user_id, calendar_date: date)
  end

  defp digest_email(email, notifications) do
    lines =
      Enum.map_join(notifications, "\n", fn notification ->
        "• #{notification.mining_process.process_number}: #{notification.process_change.field}"
      end)

    Email.new()
    |> Email.to(email)
    |> Email.from(sender())
    |> Email.subject("Alterações nas áreas que você acompanha")
    |> Email.text_body("""
    Houve alterações em processos minerários acompanhados:

    #{lines}

    Consulte os dados oficiais em #{base_url()}/notificacoes.
    Ajuste sua conta e preferências em #{base_url()}/users/settings.
    Os dados são informativos; as publicações da ANM prevalecem.
    """)
  end

  defp mark_digest_sent(digest, notifications, date, now) do
    Repo.transaction(fn ->
      ids = Enum.map(notifications, & &1.id)

      Notification
      |> where([notification], notification.id in ^ids)
      |> Repo.update_all(set: [delivered_at: now, digest_date: date, updated_at: now])

      digest
      |> Digest.changeset(%{
        status: "sent",
        sent_at: now,
        notification_count: length(ids),
        error_summary: nil
      })
      |> Repo.update!()
    end)
  end

  defp mark_digest_failed(digest, reason) do
    summary = if is_exception(reason), do: Exception.message(reason), else: inspect(reason)

    digest
    |> Digest.changeset(%{status: "failed", error_summary: String.slice(summary, 0, 240)})
    |> Repo.update()
  end

  defp get_watch(user_id, mining_process_id) do
    case Repo.get_by(Watch, user_id: user_id, mining_process_id: mining_process_id) do
      nil -> {:error, :not_found}
      watch -> {:ok, watch}
    end
  end

  defp sender,
    do: Application.get_env(:jazida_phoenix, :email_from, {"Jazida", "notificacoes@example.com"})

  defp base_url, do: JazidaPhoenixWeb.Endpoint.url()
end
