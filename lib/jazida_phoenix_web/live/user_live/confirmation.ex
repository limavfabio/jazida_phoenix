defmodule JazidaPhoenixWeb.UserLive.Confirmation do
  use JazidaPhoenixWeb, :live_view

  alias JazidaPhoenix.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm px-4 py-16">
        <div class="text-center">
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
            class="inline-flex min-h-11 w-full items-center justify-center rounded-xl bg-[#ff5d39] px-4 text-sm font-bold text-white transition hover:bg-[#ee4927]"
          >
            Confirmar e manter conectado
          </.button>
          <.button
            phx-disable-with="Confirmando..."
            class="mt-2 inline-flex min-h-11 w-full items-center justify-center rounded-xl border border-[#183128]/15 bg-white px-4 text-sm font-bold transition hover:border-[#183128]/40"
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
              class="inline-flex min-h-11 w-full items-center justify-center rounded-xl bg-[#ff5d39] px-4 text-sm font-bold text-white transition hover:bg-[#ee4927]"
            >
              Entrar
            </.button>
          <% else %>
            <.button
              name={@form[:remember_me].name}
              value="true"
              phx-disable-with="Entrando..."
              class="inline-flex min-h-11 w-full items-center justify-center rounded-xl bg-[#ff5d39] px-4 text-sm font-bold text-white transition hover:bg-[#ee4927]"
            >
              Manter conectado neste dispositivo
            </.button>
            <.button
              phx-disable-with="Entrando..."
              class="mt-2 inline-flex min-h-11 w-full items-center justify-center rounded-xl border border-[#183128]/15 bg-white px-4 text-sm font-bold transition hover:border-[#183128]/40"
            >
              Entrar somente desta vez
            </.button>
          <% end %>
        </.form>

        <p
          :if={!@user.confirmed_at}
          class="mt-8 rounded-xl border border-[#183128]/15 bg-white p-4 text-sm text-[#527065]"
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
