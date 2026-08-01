defmodule JazidaPhoenixWeb.ExplorerLive do
  use JazidaPhoenixWeb, :live_view

  alias JazidaPhoenix.{Mining, Notifications}

  @filter_keys ~w(q state category municipality substance status regime round)

  @impl true
  def mount(_params, _session, socket) do
    mining_config = Application.fetch_env!(:jazida_phoenix, :mining)

    {:ok,
     socket
     |> assign(:page_title, "Explore oportunidades minerais")
     |> assign(:map_style_url, mining_config[:map_style_url])
     |> assign(:satellite_tilejson_url, mining_config[:satellite_tilejson_url])
     |> assign(:states_geojson_url_template, mining_config[:states_geojson_url_template])
     |> assign(:selected_process, nil)
     |> assign(:watched?, false)
     |> assign(:results_empty?, true)
     |> assign(:source_import, Mining.latest_successful_import("sople_stock"))
     |> assign(:latest_source_import, Mining.latest_import("sople_stock"))
     |> assign(:stale?, Mining.stale?("sople_stock"))
     |> stream(:processes, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Map.take(params, @filter_keys)
    processes = Mining.list_processes(filters)
    selected = selected_process(params)

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:filter_form, to_form(filters, as: :filters))
      |> assign(:results_empty?, processes == [])
      |> assign(:selected_process, selected)
      |> assign(
        :watched?,
        selected && Notifications.watched?(socket.assigns.current_scope, selected.id)
      )
      |> stream(:processes, processes, reset: true)
      |> push_event("map:filters", %{category: filters["category"], state: filters["state"]})

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    params =
      socket.assigns.filters
      |> Map.merge(Map.take(filters, @filter_keys))
      |> compact_params()

    {:noreply, push_patch(socket, to: ~p"/?#{params}")}
  end

  def handle_event("clear_filters", _params, socket),
    do: {:noreply, push_patch(socket, to: ~p"/")}

  def handle_event("select_process", %{"id" => id}, socket) do
    params = socket.assigns.filters |> Map.put("process", id) |> compact_params()
    {:noreply, push_patch(socket, to: ~p"/?#{params}")}
  end

  def handle_event("close_process", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/?#{compact_params(socket.assigns.filters)}")}
  end

  def handle_event("watch", _params, %{assigns: %{current_scope: nil}} = socket) do
    {:noreply, push_navigate(socket, to: ~p"/users/log-in")}
  end

  def handle_event("watch", _params, socket) do
    {:ok, _watch} =
      Notifications.watch(socket.assigns.current_scope, socket.assigns.selected_process.id)

    {:noreply, assign(socket, :watched?, true)}
  end

  def handle_event("unwatch", _params, socket) do
    :ok = Notifications.unwatch(socket.assigns.current_scope, socket.assigns.selected_process.id)
    {:noreply, assign(socket, :watched?, false)}
  end

  defp selected_process(%{"process" => id}), do: Mining.get_process(id)
  defp selected_process(_params), do: nil

  defp compact_params(params) do
    Map.reject(params, fn {_key, value} -> value in [nil, ""] end)
  end

  defp category_label("pending_analysis"), do: "Para análise"
  defp category_label("under_analysis"), do: "Em análise"
  defp category_label("eligible"), do: "Apta"
  defp category_label("not_eligible"), do: "Não apta"
  defp category_label("free"), do: "Livre"
  defp category_label("awarded"), do: "Arrematada"
  defp category_label("awaiting_auction"), do: "Aguardando leilão"
  defp category_label("requested"), do: "Requerida"
  defp category_label("unrequested"), do: "Não requerida"
  defp category_label("suspended"), do: "Suspensa"
  defp category_label("withdrawn"), do: "Retirada"
  defp category_label("cancelled"), do: "Edital cancelado"
  defp category_label("unknown"), do: "Status não mapeado"
  defp category_label(category), do: category || "Sem categoria"

  defp category_color("eligible"), do: "bg-emerald-500"
  defp category_color("free"), do: "bg-cyan-500"
  defp category_color("pending_analysis"), do: "bg-amber-400"
  defp category_color("under_analysis"), do: "bg-orange-500"
  defp category_color("not_eligible"), do: "bg-stone-400"

  defp category_color(category) when category in ~w(withdrawn cancelled suspended),
    do: "bg-slate-500"

  defp category_color(_category), do: "bg-[#ff5d39]"

  defp blank_fallback(""), do: "—"
  defp blank_fallback(value), do: value

  defp official_process_url(process_number) do
    "https://sistemas.anm.gov.br/SCM/Extra/site/admin/dadosProcesso.aspx?numero=#{URI.encode_www_form(process_number)}"
  end
end
