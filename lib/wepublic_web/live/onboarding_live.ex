defmodule WepublicWeb.OnboardingLive do
  use WepublicWeb, :live_view

  alias Wepublic.Accounts
  alias Wepublic.Accounts.User
  alias Wepublic.Verification

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    socket =
      socket
      |> assign(:user, user)
      |> assign(:step, determine_step(user))
      |> assign(:did_form, to_form(%{"did" => user.did || ""}))
      |> assign(:feed_form, to_form(%{"feed_url" => user.feed_url || ""}))
      |> assign(:verifying, false)
      |> assign(:error, nil)

    {:ok, socket}
  end

  defp determine_step(user) do
    cond do
      not User.did_verified?(user) -> :did
      not User.feed_verified?(user) -> :feed
      not User.onboarding_complete?(user) -> :complete
      true -> :done
    end
  end

  @impl true
  def handle_event("save_did", %{"did" => did}, socket) do
    user = socket.assigns.user

    case Accounts.start_did_verification(user, did) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(:user, updated_user)
         |> assign(:error, nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :error, format_errors(changeset))}
    end
  end

  def handle_event("verify_did", _, socket) do
    socket = assign(socket, :verifying, true)

    case Verification.verify_did(socket.assigns.user) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(:user, updated_user)
         |> assign(:step, :feed)
         |> assign(:verifying, false)
         |> assign(:error, nil)}

      {:error, :token_not_found} ->
        {:noreply,
         socket
         |> assign(:verifying, false)
         |> assign(:error, "Verification token not found in your DID document. Please add it and try again.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:verifying, false)
         |> assign(:error, "Verification failed: #{inspect(reason)}")}
    end
  end

  def handle_event("save_feed", %{"feed_url" => feed_url}, socket) do
    user = socket.assigns.user

    case Accounts.update_feed_url(user, feed_url) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(:user, updated_user)
         |> assign(:error, nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :error, format_errors(changeset))}
    end
  end

  def handle_event("verify_feed", _, socket) do
    socket = assign(socket, :verifying, true)

    case Verification.verify_feed(socket.assigns.user) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(:user, updated_user)
         |> assign(:step, :complete)
         |> assign(:verifying, false)
         |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:verifying, false)
         |> assign(:error, "Feed verification failed: #{inspect(reason)}")}
    end
  end

  def handle_event("skip_did", _, socket) do
    {:noreply, assign(socket, :step, :feed)}
  end

  def handle_event("skip_feed", _, socket) do
    {:noreply, assign(socket, :step, :complete)}
  end

  def handle_event("complete_onboarding", _, socket) do
    case Accounts.complete_onboarding(socket.assigns.user) do
      {:ok, _user} ->
        {:noreply, push_navigate(socket, to: ~p"/")}

      {:error, _} ->
        {:noreply, assign(socket, :error, "Failed to complete onboarding")}
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900 text-white">
      <div class="max-w-2xl mx-auto px-4 py-12">
        <div class="text-center mb-12">
          <h1 class="text-3xl font-bold mb-2">Welcome to Wepublic</h1>
          <p class="text-gray-400">Let's verify your web presence</p>
        </div>

        <div class="flex justify-center mb-8">
          <.step_indicator
            step={1}
            label="DID"
            current={@step}
            completed={User.did_verified?(@user)}
          />
          <div class="w-12 h-0.5 bg-gray-700 self-center mx-2"></div>
          <.step_indicator
            step={2}
            label="Feed"
            current={@step}
            completed={User.feed_verified?(@user)}
          />
          <div class="w-12 h-0.5 bg-gray-700 self-center mx-2"></div>
          <.step_indicator
            step={3}
            label="Done"
            current={@step}
            completed={User.onboarding_complete?(@user)}
          />
        </div>

        <div :if={@error} class="mb-6 p-4 bg-red-900/50 border border-red-500 rounded-lg">
          <p class="text-red-300">{@error}</p>
        </div>

        <div class="bg-gray-800 rounded-xl p-8">
          <%= case @step do %>
            <% :did -> %>
              <.did_step
                user={@user}
                form={@did_form}
                verifying={@verifying}
              />
            <% :feed -> %>
              <.feed_step
                user={@user}
                form={@feed_form}
                verifying={@verifying}
              />
            <% :complete -> %>
              <.complete_step user={@user} />
            <% :done -> %>
              <.done_step />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp step_indicator(assigns) do
    completed = assigns.completed
    current = step_to_number(assigns.current) == assigns.step

    status =
      cond do
        completed -> :completed
        current -> :current
        true -> :pending
      end

    assigns = assign(assigns, :status, status)

    ~H"""
    <div class="flex flex-col items-center">
      <div class={[
        "w-10 h-10 rounded-full flex items-center justify-center text-sm font-bold",
        @status == :completed && "bg-green-500 text-white",
        @status == :current && "bg-blue-500 text-white",
        @status == :pending && "bg-gray-700 text-gray-400"
      ]}>
        <%= if @status == :completed do %>
          ✓
        <% else %>
          {@step}
        <% end %>
      </div>
      <span class={[
        "text-xs mt-1",
        @status == :current && "text-blue-400",
        @status != :current && "text-gray-500"
      ]}>
        {@label}
      </span>
    </div>
    """
  end

  defp step_to_number(:did), do: 1
  defp step_to_number(:feed), do: 2
  defp step_to_number(:complete), do: 3
  defp step_to_number(:done), do: 4

  defp did_step(assigns) do
    ~H"""
    <div>
      <h2 class="text-xl font-bold mb-4">Verify Your DID</h2>

      <div class="prose prose-invert prose-sm mb-6">
        <p>
          A <strong>Decentralized Identifier (DID)</strong> proves you control a web domain.
          This establishes your identity in the Wepublic network.
        </p>
      </div>

      <.form
        for={@form}
        phx-submit="save_did"
        class="space-y-4"
      >
        <div>
          <label class="block text-sm font-medium text-gray-300 mb-1">
            Your DID
          </label>
          <input
            type="text"
            name="did"
            value={@user.did || ""}
            placeholder="did:web:yourdomain.com"
            class="w-full bg-gray-700 border border-gray-600 rounded-lg px-4 py-2 text-white placeholder-gray-400 focus:outline-none focus:border-blue-500"
          />
          <p class="text-xs text-gray-400 mt-1">
            Example: did:web:example.com or did:web:example.com:users:alice
          </p>
        </div>

        <button
          type="submit"
          class="w-full bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-lg transition"
        >
          Save DID
        </button>
      </.form>

      <div :if={@user.did && @user.did_verification_token} class="mt-6 p-4 bg-gray-700 rounded-lg">
        <h3 class="font-medium mb-2">Verification Instructions</h3>
        <ol class="text-sm text-gray-300 space-y-2 list-decimal list-inside">
          <li>
            Add this token to your DID document at
            <code class="bg-gray-800 px-1 rounded">{did_document_url(@user.did)}</code>
          </li>
          <li>
            Include it anywhere in the document (e.g., in <code class="bg-gray-800 px-1 rounded">alsoKnownAs</code>
            or a custom field)
          </li>
          <li>Click "Verify" once your document is updated</li>
        </ol>

        <div class="mt-4 p-3 bg-gray-800 rounded font-mono text-sm break-all">
          {@user.did_verification_token}
        </div>

        <button
          phx-click="verify_did"
          disabled={@verifying}
          class="mt-4 w-full bg-green-600 hover:bg-green-700 disabled:bg-gray-600 text-white font-medium py-2 px-4 rounded-lg transition"
        >
          <%= if @verifying do %>
            Verifying...
          <% else %>
            Verify DID
          <% end %>
        </button>
      </div>

      <button
        phx-click="skip_did"
        class="mt-4 w-full text-gray-400 hover:text-white text-sm py-2 transition"
      >
        Skip for now
      </button>
    </div>
    """
  end

  defp did_document_url("did:web:" <> domain_path) do
    parts = String.split(domain_path, ":")

    case parts do
      [domain] -> "https://#{domain}/.well-known/did.json"
      [domain | path_parts] -> "https://#{domain}/#{Enum.join(path_parts, "/")}/did.json"
    end
  end

  defp did_document_url(_), do: ""

  defp feed_step(assigns) do
    ~H"""
    <div>
      <h2 class="text-xl font-bold mb-4">Verify Your Feed</h2>

      <div class="prose prose-invert prose-sm mb-6">
        <p>
          Link your <strong>RSS or Atom feed</strong> to share your content with the network.
          Your posts, products, and updates will appear in your profile.
        </p>
        <p class="text-amber-400">
          💡 If you sell products or services, they'll be highlighted on your avatar!
        </p>
      </div>

      <.form
        for={@form}
        phx-submit="save_feed"
        class="space-y-4"
      >
        <div>
          <label class="block text-sm font-medium text-gray-300 mb-1">
            Feed URL
          </label>
          <input
            type="url"
            name="feed_url"
            value={@user.feed_url || ""}
            placeholder="https://yourdomain.com/feed.xml"
            class="w-full bg-gray-700 border border-gray-600 rounded-lg px-4 py-2 text-white placeholder-gray-400 focus:outline-none focus:border-blue-500"
          />
          <p class="text-xs text-gray-400 mt-1">
            RSS, Atom, or JSON Feed URL
          </p>
        </div>

        <button
          type="submit"
          class="w-full bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-lg transition"
        >
          Save Feed URL
        </button>
      </.form>

      <div :if={@user.feed_url} class="mt-6">
        <button
          phx-click="verify_feed"
          disabled={@verifying}
          class="w-full bg-green-600 hover:bg-green-700 disabled:bg-gray-600 text-white font-medium py-2 px-4 rounded-lg transition"
        >
          <%= if @verifying do %>
            Verifying...
          <% else %>
            Verify Feed
          <% end %>
        </button>
      </div>

      <button
        phx-click="skip_feed"
        class="mt-4 w-full text-gray-400 hover:text-white text-sm py-2 transition"
      >
        Skip for now
      </button>
    </div>
    """
  end

  defp complete_step(assigns) do
    ~H"""
    <div class="text-center">
      <div class="text-6xl mb-4">🎉</div>
      <h2 class="text-xl font-bold mb-4">You're All Set!</h2>

      <div class="text-left bg-gray-700 rounded-lg p-4 mb-6">
        <h3 class="font-medium mb-2">Your Verification Status</h3>
        <ul class="space-y-2 text-sm">
          <li class="flex items-center gap-2">
            <%= if User.did_verified?(@user) do %>
              <span class="text-green-400">✓</span>
              <span>DID verified: {@user.did}</span>
            <% else %>
              <span class="text-gray-500">○</span>
              <span class="text-gray-400">DID not verified</span>
            <% end %>
          </li>
          <li class="flex items-center gap-2">
            <%= if User.feed_verified?(@user) do %>
              <span class="text-green-400">✓</span>
              <span>Feed verified: {@user.feed_title || @user.feed_url}</span>
            <% else %>
              <span class="text-gray-500">○</span>
              <span class="text-gray-400">Feed not verified</span>
            <% end %>
          </li>
        </ul>
      </div>

      <p class="text-gray-300 mb-6">
        Verification level: <strong class="text-blue-400">{User.verification_level(@user)}/2</strong>
      </p>

      <button
        phx-click="complete_onboarding"
        class="w-full bg-green-600 hover:bg-green-700 text-white font-bold py-3 px-4 rounded-lg transition"
      >
        Enter Wepublic
      </button>
    </div>
    """
  end

  defp done_step(assigns) do
    ~H"""
    <div class="text-center">
      <div class="text-6xl mb-4">✨</div>
      <h2 class="text-xl font-bold mb-4">Onboarding Complete</h2>
      <p class="text-gray-300 mb-6">You've already completed onboarding.</p>
      <.link
        navigate={~p"/"}
        class="inline-block w-full bg-blue-600 hover:bg-blue-700 text-white font-bold py-3 px-4 rounded-lg transition text-center"
      >
        Go to Map
      </.link>
    </div>
    """
  end
end
