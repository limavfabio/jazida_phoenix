defmodule JazidaPhoenixWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use JazidaPhoenixWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-full">
      <header class="relative z-50 border-b border-[#183128]/10 bg-[#f4f1e9]/95 backdrop-blur-xl">
        <div class="mx-auto flex h-16 max-w-[1600px] items-center justify-between px-4 sm:px-6">
          <.link navigate={~p"/"} class="group flex items-center gap-3" id="brand-home-link">
            <span class="grid size-9 place-items-center rounded-full bg-[#183128] text-[#e8c96a] transition-transform duration-300 group-hover:-rotate-6">
              <.icon name="hero-map" class="size-5" />
            </span>
            <span>
              <span class="font-display block text-xl leading-none font-semibold tracking-tight">Jazida</span>
              <span class="hidden font-mono text-[9px] tracking-[0.18em] text-[#527065] uppercase sm:block">Dados minerais abertos</span>
            </span>
          </.link>

          <nav
            class="flex items-center gap-1 text-sm font-semibold"
            aria-label="Navegação principal"
          >
            <.link navigate={~p"/"} class="rounded-full px-3 py-2 transition hover:bg-[#183128]/7">Explorar</.link>
            <%= if @current_scope do %>
              <.link
                navigate={~p"/notificacoes"}
                class="rounded-full px-3 py-2 transition hover:bg-[#183128]/7"
                id="nav-notifications"
              >
                Alertas
              </.link>
              <.link
                navigate={~p"/users/settings"}
                class="hidden rounded-full px-3 py-2 transition hover:bg-[#183128]/7 sm:inline-flex"
              >
                {@current_scope.user.email}
              </.link>
              <.link
                href={~p"/users/log-out"}
                method="delete"
                class="rounded-full border border-[#183128]/15 px-3 py-2 transition hover:border-[#183128]/40"
              >
                Sair
              </.link>
            <% else %>
              <.link
                navigate={~p"/users/log-in"}
                class="rounded-full px-3 py-2 transition hover:bg-[#183128]/7"
              >Entrar</.link>
              <.link
                navigate={~p"/users/register"}
                class="rounded-full bg-[#ff5d39] px-4 py-2 text-white shadow-[0_6px_20px_rgba(255,93,57,.24)] transition hover:-translate-y-0.5 hover:bg-[#ee4927]"
              >
                Criar conta
              </.link>
            <% end %>
          </nav>
        </div>
      </header>

      <main>{render_slot(@inner_block)}</main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
