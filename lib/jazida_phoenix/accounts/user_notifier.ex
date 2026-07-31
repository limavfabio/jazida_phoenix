defmodule JazidaPhoenix.Accounts.UserNotifier do
  import Swoosh.Email

  alias JazidaPhoenix.Mailer
  alias JazidaPhoenix.Accounts.User

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(
        Application.get_env(:jazida_phoenix, :email_from, {"Jazida", "notificacoes@example.com"})
      )
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Confirme a alteração do seu e-mail", """

    ==============================

    Olá, #{user.email}.

    Confirme a alteração do seu e-mail acessando o link abaixo:

    #{url}

    Se você não solicitou esta alteração, ignore esta mensagem.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(user.email, "Seu link de acesso à Jazida", """

    ==============================

    Olá, #{user.email}.

    Entre na sua conta acessando o link abaixo:

    #{url}

    Se você não solicitou este acesso, ignore esta mensagem.

    ==============================
    """)
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirme sua conta na Jazida", """

    ==============================

    Olá, #{user.email}.

    Confirme sua conta acessando o link abaixo:

    #{url}

    Se você não criou esta conta, ignore esta mensagem.

    ==============================
    """)
  end
end
