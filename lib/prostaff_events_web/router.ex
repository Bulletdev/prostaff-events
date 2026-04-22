defmodule ProstaffEventsWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ProstaffEventsWeb do
    pipe_through :api

    get "/health", EventsController, :health
    post "/events/notify", EventsController, :notify
  end
end
