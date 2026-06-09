defmodule ProstaffEventsWeb.ChannelCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest

      @endpoint ProstaffEventsWeb.Endpoint

      import ProstaffEventsWeb.ChannelCase
    end
  end

  setup do
    :ok
  end

  @doc "Builds a signed JWT for use in socket/channel tests."
  def user_token(claims \\ %{}) do
    secret = Application.fetch_env!(:prostaff_events, :internal_jwt_secret)
    signer = Joken.Signer.create("HS256", secret)

    base = %{
      "user_id" => claims[:user_id] || "user-123",
      "org_id" => claims[:org_id] || "org-abc"
    }

    {:ok, token, _} = Joken.encode_and_sign(base, signer)
    token
  end
end
