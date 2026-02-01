defmodule Wepublic.IdentityTest do
  use ExUnit.Case, async: true

  alias Wepublic.Identity
  alias Wepublic.Identity.Keypair

  describe "keypair generation" do
    test "generates valid Ed25519 keypair" do
      keypair = Identity.generate_keypair()

      assert is_binary(keypair.public_key)
      assert is_binary(keypair.private_key)
      assert byte_size(keypair.public_key) == 32
      # Private key is the 32-byte seed
      assert byte_size(keypair.private_key) == 32
    end

    test "generates unique keypairs" do
      keypair1 = Identity.generate_keypair()
      keypair2 = Identity.generate_keypair()

      refute keypair1.public_key == keypair2.public_key
    end
  end

  describe "did:key encoding" do
    test "encodes public key to did:key format" do
      keypair = Identity.generate_keypair()
      did = Identity.public_key_to_did(keypair.public_key)

      assert String.starts_with?(did, "did:key:z")
    end

    test "decodes did:key back to public key" do
      keypair = Identity.generate_keypair()
      did = Identity.public_key_to_did(keypair.public_key)

      assert {:ok, decoded_key} = Identity.did_to_public_key(did)
      assert decoded_key == keypair.public_key
    end

    test "rejects invalid did format" do
      assert {:error, :invalid_did_format} = Identity.did_to_public_key("not-a-did")
    end
  end

  describe "signing actions" do
    test "signs and verifies an action" do
      keypair = Identity.generate_keypair()

      action = %{
        type: "profile_update",
        display_name: "Alice",
        avatar_color: "#ff0000"
      }

      signed = Identity.sign_action(action, keypair.private_key)

      assert signed.action == action
      assert String.starts_with?(signed.did, "did:key:z")
      assert is_binary(signed.signature)
      assert is_binary(signed.timestamp)

      # Verify with embedded did
      assert {:ok, ^action} = Identity.verify_action(signed)

      # Verify with explicit public key
      assert {:ok, ^action} = Identity.verify_action(signed, keypair.public_key)
    end

    test "rejects tampered action" do
      keypair = Identity.generate_keypair()

      action = %{type: "post", content: "Hello"}
      signed = Identity.sign_action(action, keypair.private_key)

      # Tamper with the action
      tampered = %{signed | action: %{type: "post", content: "Hacked"}}

      assert {:error, :invalid_signature} = Identity.verify_action(tampered)
    end

    test "rejects wrong public key" do
      keypair1 = Identity.generate_keypair()
      keypair2 = Identity.generate_keypair()

      action = %{type: "connection_request", to: "did:key:z123"}
      signed = Identity.sign_action(action, keypair1.private_key)

      # Verify with wrong key
      assert {:error, :invalid_signature} = Identity.verify_action(signed, keypair2.public_key)
    end
  end

  describe "keypair export/import" do
    test "exports and imports keypair" do
      keypair = Identity.generate_keypair()
      exported = Keypair.export(keypair)

      assert is_binary(exported.public_key)
      assert is_binary(exported.private_key)
      assert String.starts_with?(exported.did, "did:key:z")

      # Import and verify
      {:ok, imported} = Keypair.import_keypair(exported)
      assert imported.public_key == keypair.public_key
      assert imported.private_key == keypair.private_key
    end
  end
end
