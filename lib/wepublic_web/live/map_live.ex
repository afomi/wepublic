defmodule WepublicWeb.MapLive do
  use WepublicWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="neighborhood-container"
      phx-hook="Neighborhood"
      class="w-full h-screen">
    </div>

    <div
      id="neighborhood-info"
      class="fixed top-12 left-2.5 z-40 text-white font-mono text-xs bg-black/70 p-3 rounded-lg max-w-60">
      <div class="text-sm font-bold mb-2">
        Vacaville, CA
      </div>
      <div class="text-gray-400 mb-3">
        38.3566°N, 121.9877°W
      </div>
      <div
        id="figure-list"
        class="border-t border-gray-600 pt-2">
      </div>
    </div>
    """
  end
end
