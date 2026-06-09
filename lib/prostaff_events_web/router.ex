defmodule ProstaffEventsWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ProstaffEventsWeb do
    pipe_through :api

    get "/health", EventsController, :health
    get "/health/ready", EventsController, :ready
    post "/events/notify", EventsController, :notify
  end
end
