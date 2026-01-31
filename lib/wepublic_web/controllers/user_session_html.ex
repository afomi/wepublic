defmodule WepublicWeb.UserSessionHTML do
  use WepublicWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:wepublic, Wepublic.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
