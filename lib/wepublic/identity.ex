defmodule Wepublic.Identity do
  @moduledoc """
  Cryptographic identity management for user sovereignty.

  Users can own all their data through a single keypair:
  - Public key serves as their decentralized identifier
  - Private key signs all their actions (profile, connections, posts)
  - Signatures make data portable and verifiable without central authority

  Supports:
  - did:key (pure keypair-derived, fully self-sovereign)
  - did:web (DNS-based, easier onboarding)
  - Ed25519 signatures (fast, secure, compact)
  """

  alias Wepublic.Identity.{Keypair, SignedAction}

  @doc """
  Generates a new Ed25519 keypair for a user.
  Returns both keys - the private key should be securely stored by the user.
  """
  def generate_keypair do
    Keypair.generate()
  end

  @doc """
  Derives a did:key identifier from a public key.
  Format: did:key:z6Mk... (multibase-encoded Ed25519 public key)
  """
  def public_key_to_did(public_key) do
    Keypair.to_did_key(public_key)
  end

  @doc """
  Extracts the public key from a did:key identifier.
  """
  def did_to_public_key("did:key:" <> encoded) do
    Keypair.from_did_key(encoded)
  end

  def did_to_public_key(_), do: {:error, :invalid_did_format}

  @doc """
  Signs an action with the user's private key.
  The action becomes portable and verifiable by anyone.
  """
  def sign_action(action, private_key) do
    SignedAction.sign(action, private_key)
  end

  @doc """
  Verifies a signed action against the claimed public key.
  Returns {:ok, action} if valid, {:error, reason} if not.
  """
  def verify_action(signed_action, public_key) do
    SignedAction.verify(signed_action, public_key)
  end

  @doc """
  Verifies a signed action using the embedded did:key.
  """
  def verify_action(signed_action) do
    SignedAction.verify(signed_action)
  end
end
