defmodule ProstaffEvents.RailsClient.Http do
  @moduledoc false
  @behaviour ProstaffEvents.RailsClient

  require Logger

  @impl true
  def get_active_queues do
    rails_url = Application.get_env(:prostaff_events, :rails_api_url)
    token = generate_internal_token()

    case Req.get("#{rails_url}/internal/api/inhouse_queues/active",
           headers: [{"authorization", "Bearer #{token}"}],
           receive_timeout: 5_000
         ) do
      {:ok, %{status: 200, body: %{"queues" => queues}}} -> {:ok, queues}
      {:ok, resp} -> {:error, "unexpected status #{resp.status}"}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp generate_internal_token do
    secret = Application.get_env(:prostaff_events, :internal_jwt_secret, "")
    signer = Joken.Signer.create("HS256", secret)

    claims = %{
      "type" => "internal",
      "iss" => "prostaff-events",
      "iat" => DateTime.to_unix(DateTime.utc_now())
    }

    {:ok, token, _} = Joken.encode_and_sign(claims, signer)
    token
  end
end
