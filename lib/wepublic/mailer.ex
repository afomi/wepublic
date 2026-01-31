defmodule Wepublic.Mailer do
  use Swoosh.Mailer, otp_app: :wepublic

  @doc """
  Delivers an email with CSS inlined using Premailex.
  Useful for email clients that don't support <style> tags.
  """
  def deliver_with_inline_css(email) do
    email
    |> inline_css()
    |> deliver()
  end

  defp inline_css(%Swoosh.Email{html_body: nil} = email), do: email

  defp inline_css(%Swoosh.Email{html_body: html} = email) do
    %{email | html_body: Premailex.to_inline_css(html)}
  end
end
