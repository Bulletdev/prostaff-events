defmodule ProstaffEvents.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Registry for InhouseQueue GenServers — keyed by "org_id:queue_id"
      {Registry, keys: :unique, name: ProstaffEvents.InhouseQueue.Registry},

      # Phoenix PubSub — broadcast hub for all channels
      {Phoenix.PubSub, name: ProstaffEvents.PubSub},

      # Redis subscriber — listens on prostaff:events:* channels published by Rails
      ProstaffEvents.RedisSubscriber,

      # InhouseQueue DynamicSupervisor — one GenServer per active queue
      {DynamicSupervisor, name: ProstaffEvents.InhouseQueue.Supervisor, strategy: :one_for_one},

      # Reconcile active inhouse queues from Rails on startup
      ProstaffEvents.InhouseQueue.Reconciler,

      # Phoenix HTTP endpoint
      ProstaffEventsWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: ProstaffEvents.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    ProstaffEventsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
