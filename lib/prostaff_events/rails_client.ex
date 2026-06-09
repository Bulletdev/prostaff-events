defmodule ProstaffEvents.RailsClient do
  @moduledoc "Behaviour for fetching data from the Rails API."

  @callback get_active_queues() :: {:ok, [map()]} | {:error, term()}

  def impl, do: Application.get_env(:prostaff_events, :rails_client, __MODULE__.Http)
end
