defmodule JazidaPhoenixWeb.NotificationsLive do
  use JazidaPhoenixWeb, :live_view

  alias JazidaPhoenix.Notifications

  @impl true
  def mount(_params, _session, socket) do
    notifications = Notifications.list_notifications(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, "Alertas")
     |> assign(:notifications_empty?, notifications == [])
     |> stream(:notifications, notifications)}
  end

  @impl true
  def handle_event("mark_read", %{"id" => id}, socket) do
    with {id, ""} <- Integer.parse(id),
         :ok <- Notifications.mark_read(socket.assigns.current_scope, id) do
      notification =
        socket.assigns.current_scope
        |> Notifications.list_notifications()
        |> Enum.find(&(&1.id == id))

      {:noreply,
       if(notification, do: stream_insert(socket, :notifications, notification), else: socket)}
    else
      _ -> {:noreply, socket}
    end
  end
end
