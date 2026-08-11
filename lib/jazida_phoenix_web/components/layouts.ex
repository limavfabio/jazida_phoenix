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
      <header class="relative z-50 border-b border-[#dfe3df] bg-white">
        <div class="mx-auto flex h-14 max-w-[1600px] items-center justify-between px-4 sm:px-6">
          <.link
            navigate={~p"/"}
            class="flex items-center gap-2.5 font-semibold tracking-tight text-[#1f2823]"
            id="brand-home-link"
          >
            <span class="grid size-7 place-items-center rounded-md bg-[#1d5b45] text-white">
              <.icon name="hero-map" class="size-4" />
            </span>
            <span>Jazida</span>
          </.link>

          <nav
            class="flex items-center gap-1 text-sm"
            aria-label="Navegação principal"
          >
            <.link navigate={~p"/"} class="rounded-md px-3 py-2 transition hover:bg-[#f0f2f0]">Mapa</.link>
            <%= if @current_scope do %>
              <.link
                navigate={~p"/notificacoes"}
                class="rounded-md px-3 py-2 transition hover:bg-[#f0f2f0]"
                id="nav-notifications"
              >
                Alertas
              </.link>
              <.link
                navigate={~p"/users/settings"}
                class="hidden rounded-md px-3 py-2 transition hover:bg-[#f0f2f0] sm:inline-flex"
              >
                {@current_scope.user.email}
              </.link>
              <.link
                href={~p"/users/log-out"}
                method="delete"
                class="rounded-md px-3 py-2 text-[#69726c] transition hover:bg-[#f0f2f0] hover:text-[#1f2823]"
              >
                Sair
              </.link>
            <% else %>
              <.link
                navigate={~p"/users/log-in"}
                class="rounded-md px-3 py-2 transition hover:bg-[#f0f2f0]"
              >Entrar</.link>
              <.link
                navigate={~p"/users/register"}
                class="rounded-md bg-[#1d5b45] px-3 py-2 font-semibold text-white transition hover:bg-[#174936]"
              >
                Cadastrar
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
