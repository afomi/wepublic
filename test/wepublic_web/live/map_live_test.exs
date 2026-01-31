defmodule WepublicWeb.MapLiveTest do
  use WepublicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /" do
    test "renders the map as default route", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "neighborhood-container"
      assert html =~ ~s(phx-hook="Neighborhood")
    end
  end

  describe "GET /map" do
    test "renders the neighborhood container", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/map")
      assert html =~ "neighborhood-container"
      assert html =~ ~s(phx-hook="Neighborhood")
    end

    test "displays location info panel", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/map")
      assert html =~ "Vacaville, CA"
      assert html =~ "38.3566"
    end
  end
end
