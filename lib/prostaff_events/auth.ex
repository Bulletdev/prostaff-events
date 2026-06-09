defmodule ProstaffEvents.Auth do
  @moduledoc """
  JWT verification for WebSocket connections and internal HTTP endpoints.
  Supports both user tokens (from frontend) and internal tokens (from Rails/Scraper).
  """

  @algorithm "HS256"

  def verify_token(token) when is_binary(token) do
    secret = Application.fetch_env!(:prostaff_events, :internal_jwt_secret)
    signer = Joken.Signer.create(@algorithm, secret)

    with {:ok, claims} <- Joken.verify(token, signer),
         :ok <- check_expiry(claims) do
      extract_identity(claims)
    end
  end

  defp check_expiry(%{"exp" => exp}) when is_integer(exp) do
    if exp >= DateTime.to_unix(DateTime.utc_now()),
      do: :ok,
      else: {:error, :token_expired}
  end

  defp check_expiry(_claims), do: :ok

  def verify_api_key(provided_key) do
    expected = Application.get_env(:prostaff_events, :scraper_api_key, "")

    if expected != "" and provided_key == expected do
      :ok
    else
      {:error, :invalid_api_key}
    end
  end

  defp extract_identity(%{"user_id" => user_id, "org_id" => org_id}) do
    {:ok, %{user_id: to_string(user_id), org_id: to_string(org_id)}}
  end

  # Internal system token (from Rails services publishing events)
  defp extract_identity(%{"type" => "internal", "iss" => "prostaff-api"}) do
    {:ok, %{user_id: "system", org_id: "system"}}
  end

  defp extract_identity(_claims), do: {:error, :missing_identity_claims}
end
