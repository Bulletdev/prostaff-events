defmodule ProstaffEvents.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {Registry, keys: :unique, name: ProstaffEvents.InhouseQueue.Registry},
        {Phoenix.PubSub, name: ProstaffEvents.PubSub},
        {DynamicSupervisor, name: ProstaffEvents.InhouseQueue.Supervisor, strategy: :one_for_one},
        ProstaffEvents.RateLimit,
        ProstaffEventsWeb.Endpoint
      ] ++ runtime_children()

    opts = [strategy: :one_for_one, name: ProstaffEvents.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # RedisSubscriber and Reconciler are not started in test - tests start them
  # manually via start_supervised! to control deps and avoid ordering issues
  # with Mox mock setup.
  defp runtime_children do
    if Application.get_env(:prostaff_events, :env, :prod) == :test do
      []
    else
      redis_url = Application.get_env(:prostaff_events, :redis_url, "redis://localhost:6379/0")

      [
        %{id: Redix, start: {Redix, :start_link, [redis_url, [name: :redix]]}},
        ProstaffEvents.RedisSubscriber,
        ProstaffEvents.InhouseQueue.Reconciler
      ]
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    ProstaffEventsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
