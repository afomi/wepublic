defmodule WepublicWeb.PageControllerTest do
  use WepublicWeb.ConnCase

  describe "GET /home" do
    test "shows Wepublic branding", %{conn: conn} do
      conn = get(conn, ~p"/home")
      assert html_response(conn, 200) =~ "Wepublic"
    end

    test "shows cyberfolk concept", %{conn: conn} do
      conn = get(conn, ~p"/home")
      assert html_response(conn, 200) =~ "cyberfolk"
    end

    test "shows Enter the Map button", %{conn: conn} do
      conn = get(conn, ~p"/home")
      assert html_response(conn, 200) =~ "Enter the Map"
    end

    test "shows Sign In with GitHub button", %{conn: conn} do
      conn = get(conn, ~p"/home")
      assert html_response(conn, 200) =~ "Sign In with GitHub"
    end
  end
end
