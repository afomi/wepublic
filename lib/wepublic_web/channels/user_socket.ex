defmodule WepublicWeb.UserSocket do
  use Phoenix.Socket

  channel "conversation:*", WepublicWeb.ConversationChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Phoenix.Token.verify(WepublicWeb.Endpoint, "user socket", token, max_age: 86400) do
      {:ok, user_id} ->
        {:ok, assign(socket, :user_id, user_id)}

      {:error, _reason} ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end
