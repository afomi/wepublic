defmodule WepublicWeb.AuthController do
  use WepublicWeb, :controller

  plug Ueberauth

  alias Wepublic.Accounts
  alias Wepublic.Accounts.User

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate with GitHub.")
    |> redirect(to: ~p"/users/log-in")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    user_params = %{
      email: auth.info.email,
      github_id: auth.uid,
      github_username: auth.info.nickname,
      github_avatar_url: auth.info.image,
      display_name: auth.info.name || auth.info.nickname
    }

    case find_or_create_user(user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Welcome, #{user.display_name || user.email}!")
        |> WepublicWeb.UserAuth.log_in_user(user)

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Failed to sign in with GitHub.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  defp find_or_create_user(%{github_id: github_id} = params) do
    case Accounts.get_user_by_github_id(github_id) do
      nil -> create_github_user(params)
      user -> {:ok, user}
    end
  end

  defp create_github_user(params) do
    %User{}
    |> User.github_changeset(params)
    |> User.confirm_changeset()
    |> Wepublic.Repo.insert()
  end
end
