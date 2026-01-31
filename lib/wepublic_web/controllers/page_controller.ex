defmodule WepublicWeb.PageController do
  use WepublicWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
