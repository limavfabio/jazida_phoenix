defmodule JazidaPhoenixWeb.UserLive.Confirmation do
  use JazidaPhoenixWeb, :live_view

  alias JazidaPhoenix.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm px-4 py-12 sm:py-16">
        <div>
          <.header>Bem-vindo, {@user.email}</.header>
        </div>

        <.form
          :if={!@user.confirmed_at}
          for={@form}
          id="confirmation_form"
          phx-mounted={JS.focus_first()}
          phx-submit="submit"
          action={~p"/users/log-in?_action=confirmed"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <.button
            name={@form[:remember_me].name}
            value="true"
            phx-disable-with="Confirmando..."
            class="inline-flex min-h-11 w-full items-center justify-center rounded-md bg-[#1d5b45] px-4 text-sm font-semibold text-white transition hover:bg-[#174936]"
          >
            Confirmar e manter conectado
          </.button>
          <.button
            phx-disable-with="Confirmando..."
            class="mt-2 inline-flex min-h-11 w-full items-center justify-center rounded-md border border-[#cfd5d0] bg-white px-4 text-sm font-semibold transition hover:bg-[#f0f2f0]"
          >
            Confirmar e entrar somente desta vez
          </.button>
        </.form>

        <.form
          :if={@user.confirmed_at}
          for={@form}
          id="login_form"
          phx-submit="submit"
          phx-mounted={JS.focus_first()}
          action={~p"/users/log-in"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <%= if @current_scope do %>
            <.button
              phx-disable-with="Entrando..."
              class="inline-flex min-h-11 w-full items-center justify-center rounded-md bg-[#1d5b45] px-4 text-sm font-semibold text-white transition hover:bg-[#174936]"
            >
              Entrar
            </.button>
          <% else %>
            <.button
              name={@form[:remember_me].name}
              value="true"
              phx-disable-with="Entrando..."
              class="inline-flex min-h-11 w-full items-center justify-center rounded-md bg-[#1d5b45] px-4 text-sm font-semibold text-white transition hover:bg-[#174936]"
            >
              Manter conectado neste dispositivo
            </.button>
            <.button
              phx-disable-with="Entrando..."
              class="mt-2 inline-flex min-h-11 w-full items-center justify-center rounded-md border border-[#cfd5d0] bg-white px-4 text-sm font-semibold transition hover:bg-[#f0f2f0]"
            >
              Entrar somente desta vez
            </.button>
          <% end %>
        </.form>

        <p
          :if={!@user.confirmed_at}
          class="mt-8 rounded-md border border-[#dfe3df] bg-white p-4 text-sm text-[#69726c]"
        >
          Dica: se preferir, você pode definir uma senha nas configurações da conta.
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "user")

      {:ok, assign(socket, user: user, form: form, trigger_submit: false),
       temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, "O link de acesso é inválido ou expirou.")
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
