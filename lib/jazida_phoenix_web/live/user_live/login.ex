defmodule JazidaPhoenixWeb.UserLive.Login do
  use JazidaPhoenixWeb, :live_view

  alias JazidaPhoenix.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4 px-4 py-16">
        <div class="text-center">
          <.header>
            <p>Entrar</p>
            <:subtitle>
              <%= if @current_scope do %>
                Confirme sua identidade novamente para alterar dados sensíveis da conta.
              <% else %>
                Ainda não tem conta? <.link
                  navigate={~p"/users/register"}
                  class="font-semibold text-[#ff5d39] hover:underline"
                  phx-no-format
                >Cadastre-se</.link> agora.
              <% end %>
            </:subtitle>
          </.header>
        </div>

        <div
          :if={local_mail_adapter?()}
          class="flex gap-3 rounded-xl border border-cyan-700/15 bg-cyan-50 p-4 text-sm text-cyan-950"
        >
          <.icon name="hero-information-circle" class="size-6 shrink-0" />
          <div>
            <p>O adaptador local de e-mail está ativo.</p>
            <p>
              Veja as mensagens enviadas na <.link href="/dev/mailbox" class="underline">caixa de testes</.link>.
            </p>
          </div>
        </div>

        <.form
          for={@form}
          id="login_form_magic"
          action={~p"/users/log-in"}
          phx-submit="submit_magic"
        >
          <.input
            id="login_form_magic_email"
            readonly={!!@current_scope}
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.button
            variant="primary"
            class="inline-flex min-h-11 w-full items-center justify-center rounded-xl bg-[#ff5d39] px-4 text-sm font-bold text-white transition hover:bg-[#ee4927]"
          >
            Entrar por e-mail <span aria-hidden="true">→</span>
          </.button>
        </.form>

        <div class="flex items-center gap-3 py-2 text-xs text-[#789087] before:h-px before:flex-1 before:bg-[#183128]/10 after:h-px after:flex-1 after:bg-[#183128]/10">
          ou
        </div>

        <.form
          for={@form}
          id="login_form_password"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            id="login_form_password_email"
            readonly={!!@current_scope}
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Senha"
            autocomplete="current-password"
            spellcheck="false"
          />
          <.button
            variant="primary"
            class="inline-flex min-h-11 w-full items-center justify-center rounded-xl bg-[#ff5d39] px-4 text-sm font-bold text-white transition hover:bg-[#ee4927]"
            name={@form[:remember_me].name}
            value="true"
          >
            Entrar e manter conectado <span aria-hidden="true">→</span>
          </.button>
          <.button class="mt-2 inline-flex min-h-11 w-full items-center justify-center rounded-xl border border-[#183128]/15 bg-white px-4 text-sm font-bold transition hover:border-[#183128]/40">
            Entrar somente desta vez
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      "Se o e-mail estiver cadastrado, você receberá em breve as instruções para entrar."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:jazida_phoenix, JazidaPhoenix.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
