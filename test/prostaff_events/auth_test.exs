defmodule ProstaffEvents.AuthTest do
  use ExUnit.Case, async: true

  alias ProstaffEvents.Auth

  @secret Application.compile_env(:prostaff_events, :internal_jwt_secret, "test_jwt_secret")
  @signer Joken.Signer.create("HS256", @secret)

  defp sign(claims) do
    {:ok, token, _} = Joken.encode_and_sign(claims, @signer)
    token
  end

  describe "verify_token/1" do
    test "aceita JWT válido de usuário" do
      token = sign(%{"user_id" => "u1", "org_id" => "org1"})
      assert {:ok, %{user_id: "u1", org_id: "org1"}} = Auth.verify_token(token)
    end

    test "aceita JWT interno com iss prostaff-api" do
      token = sign(%{"type" => "internal", "iss" => "prostaff-api"})
      assert {:ok, %{user_id: "system", org_id: "system"}} = Auth.verify_token(token)
    end

    test "rejeita token expirado" do
      past = DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.to_unix()
      token = sign(%{"user_id" => "u1", "org_id" => "org1", "exp" => past})
      assert {:error, _} = Auth.verify_token(token)
    end

    test "rejeita token com assinatura inválida" do
      bad_signer = Joken.Signer.create("HS256", "wrong_secret")

      {:ok, token, _} =
        Joken.encode_and_sign(%{"user_id" => "u1", "org_id" => "org1"}, bad_signer)

      assert {:error, _} = Auth.verify_token(token)
    end

    test "rejeita token sem campos de identidade" do
      token = sign(%{"sub" => "something"})
      assert {:error, :missing_identity_claims} = Auth.verify_token(token)
    end
  end

  describe "verify_api_key/1" do
    test "aceita a chave correta" do
      assert :ok = Auth.verify_api_key("test_scraper_key")
    end

    test "rejeita chave incorreta" do
      assert {:error, :invalid_api_key} = Auth.verify_api_key("wrong_key")
    end

    test "rejeita nil" do
      assert {:error, :invalid_api_key} = Auth.verify_api_key(nil)
    end
  end
end
