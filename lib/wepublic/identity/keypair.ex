defmodule Wepublic.Identity.Keypair do
  @moduledoc """
  Ed25519 keypair generation and did:key encoding.

  Ed25519 chosen for:
  - Fast signing and verification
  - Small keys (32 bytes) and signatures (64 bytes)
  - Widely supported, battle-tested
  - Deterministic signatures (no nonce reuse vulnerabilities)
  """

  # Multicodec prefix for Ed25519 public key
  @ed25519_multicodec_prefix <<0xED, 0x01>>

  @doc """
  Generates a new Ed25519 keypair.
  Returns %{public_key: binary, private_key: binary, seed: binary}

  Note: Erlang's :crypto returns private_key as 32-byte seed.
  We store both the seed (for signing) and public_key (for verification).
  """
  def generate do
    {public_key, seed} = :crypto.generate_key(:eddsa, :ed25519)

    %{
      public_key: public_key,
      private_key: seed,
      seed: seed
    }
  end

  @doc """
  Signs a message with an Ed25519 private key (seed).
  """
  def sign(message, seed) when is_binary(message) and is_binary(seed) do
    :crypto.sign(:eddsa, :none, message, [seed, :ed25519])
  end

  @doc """
  Verifies a signature against a message and public key.
  """
  def verify(message, signature, public_key)
      when is_binary(message) and is_binary(signature) and is_binary(public_key) do
    :crypto.verify(:eddsa, :none, message, signature, [public_key, :ed25519])
  end

  @doc """
  Converts a public key to a did:key identifier.

  Format: did:key:z{multibase-base58btc-encoded(multicodec-prefix + public-key)}

  The 'z' prefix indicates base58btc encoding (multibase).
  The multicodec prefix 0xed01 indicates Ed25519 public key.
  """
  def to_did_key(public_key) when is_binary(public_key) do
    encoded =
      (@ed25519_multicodec_prefix <> public_key)
      |> Base58.encode()

    "did:key:z#{encoded}"
  end

  @doc """
  Extracts public key from a did:key multibase-encoded string.
  Input should be the part after "did:key:" (e.g., "z6Mk...")
  """
  def from_did_key("z" <> base58_encoded) do
    case Base58.decode(base58_encoded) do
      <<0xED, 0x01, public_key::binary-size(32)>> ->
        {:ok, public_key}

      <<0xED, 0x01, _::binary>> ->
        {:error, :invalid_key_length}

      _ ->
        {:error, :invalid_multicodec}
    end
  rescue
    _ -> {:error, :invalid_base58}
  end

  def from_did_key(_), do: {:error, :invalid_multibase_prefix}

  @doc """
  Exports keypair for user backup.
  Returns a map with base64-encoded keys for safe storage/transmission.
  """
  def export(%{public_key: pub, private_key: priv}) do
    %{
      public_key: Base.url_encode64(pub, padding: false),
      private_key: Base.url_encode64(priv, padding: false),
      did: to_did_key(pub)
    }
  end

  @doc """
  Imports keypair from exported format.
  """
  def import_keypair(%{"private_key" => priv_b64}) do
    import_keypair(%{private_key: priv_b64})
  end

  def import_keypair(%{private_key: seed_b64}) do
    with {:ok, seed} <- Base.url_decode64(seed_b64, padding: false) do
      case seed do
        <<seed::binary-size(32)>> ->
          # Derive public key from seed
          {public_key, _} = :crypto.generate_key(:eddsa, :ed25519, seed)
          {:ok, %{public_key: public_key, private_key: seed, seed: seed}}

        _ ->
          {:error, :invalid_private_key_length}
      end
    end
  end
end
