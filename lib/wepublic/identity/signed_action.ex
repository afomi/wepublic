defmodule Wepublic.Identity.SignedAction do
  @moduledoc """
  Signed user actions that are portable and self-verifying.

  Every action a user takes can be signed, making it:
  - Verifiable: Anyone can confirm the user authored it
  - Portable: Move between servers without losing provenance
  - Immutable: Tampering invalidates the signature
  - Timestamped: Signed timestamp proves when action was claimed

  Action types:
  - profile_update: Changes to display name, avatar, website
  - connection_request: Request to connect with another user
  - connection_accept: Accepting a connection request
  - post: Content published to feed
  - beacon_presence: Checking in at a beacon
  - endorsement: Vouching for another user
  """

  alias Wepublic.Identity.Keypair

  @doc """
  Signs an action with the user's private key.

  Returns a signed action envelope containing:
  - action: The original action data
  - did: The signer's did:key
  - timestamp: When the action was signed (ISO8601)
  - signature: Ed25519 signature over canonical JSON of above
  """
  def sign(action, seed) when is_map(action) and is_binary(seed) do
    # Derive public key from seed to get the DID
    {public_key, _} = :crypto.generate_key(:eddsa, :ed25519, seed)
    did = Keypair.to_did_key(public_key)

    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    # Canonical payload to sign
    payload = %{
      action: action,
      did: did,
      timestamp: timestamp
    }

    payload_json = canonical_json(payload)
    signature = Keypair.sign(payload_json, seed)

    %{
      action: action,
      did: did,
      timestamp: timestamp,
      signature: Base.url_encode64(signature, padding: false)
    }
  end

  @doc """
  Verifies a signed action using the embedded did:key.
  """
  def verify(%{action: action, did: did, timestamp: timestamp, signature: sig_b64}) do
    with {:ok, public_key} <- extract_public_key(did),
         {:ok, signature} <- Base.url_decode64(sig_b64, padding: false) do
      payload = %{
        action: action,
        did: did,
        timestamp: timestamp
      }

      payload_json = canonical_json(payload)

      if Keypair.verify(payload_json, signature, public_key) do
        {:ok, action}
      else
        {:error, :invalid_signature}
      end
    end
  end

  def verify(%{"action" => _, "did" => _, "timestamp" => _, "signature" => _} = signed) do
    signed
    |> atomize_keys()
    |> verify()
  end

  def verify(_), do: {:error, :malformed_signed_action}

  @doc """
  Verifies a signed action against a specific public key.
  Use when you already know/trust the expected signer.
  """
  def verify(%{action: action, did: did, timestamp: timestamp, signature: sig_b64}, public_key) do
    with {:ok, signature} <- Base.url_decode64(sig_b64, padding: false) do
      payload = %{
        action: action,
        did: did,
        timestamp: timestamp
      }

      payload_json = canonical_json(payload)

      if Keypair.verify(payload_json, signature, public_key) do
        {:ok, action}
      else
        {:error, :invalid_signature}
      end
    end
  end

  @doc """
  Checks if a signed action's timestamp is within acceptable bounds.
  Prevents replay attacks with old signed actions.
  """
  def timestamp_valid?(%{timestamp: timestamp}, max_age_seconds \\ 300) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _} ->
        age = DateTime.diff(DateTime.utc_now(), dt, :second)
        age >= 0 and age <= max_age_seconds

      _ ->
        false
    end
  end

  # Canonical JSON encoding for consistent signatures
  # Keys sorted alphabetically, no whitespace
  defp canonical_json(data) do
    data
    |> sort_keys()
    |> Jason.encode!()
  end

  defp sort_keys(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {k, _} -> to_string(k) end)
    |> Enum.map(fn {k, v} -> {k, sort_keys(v)} end)
    |> Map.new()
  end

  defp sort_keys(list) when is_list(list), do: Enum.map(list, &sort_keys/1)
  defp sort_keys(other), do: other

  defp extract_public_key("did:key:z" <> _ = did) do
    Wepublic.Identity.did_to_public_key(did)
  end

  defp extract_public_key(_), do: {:error, :unsupported_did_method}

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), atomize_keys(v)}
      {k, v} -> {k, atomize_keys(v)}
    end)
  end

  defp atomize_keys(other), do: other
end
