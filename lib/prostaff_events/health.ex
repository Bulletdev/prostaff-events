defmodule ProstaffEvents.Health do
  @moduledoc false

  @doc "Checks Redis connectivity and Rails API reachability."
  def ready do
    checks = [redis: check_redis(), rails: check_rails()]
    failed = Enum.filter(checks, fn {_, v} -> v != :ok end)

    if failed == [] do
      {:ok, Map.new(checks, fn {k, _} -> {k, "ok"} end)}
    else
      {:error, Map.new(checks, fn {k, v} -> {k, format(v)} end)}
    end
  end

  defp check_redis do
    case Redix.command(:redix, ["PING"]) do
      {:ok, "PONG"} -> :ok
      other -> {:error, inspect(other)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  catch
    :exit, reason -> {:error, inspect(reason)}
  end

  defp check_rails do
    rails_url = Application.get_env(:prostaff_events, :rails_api_url, "")

    case Req.get("#{rails_url}/health", receive_timeout: 3_000, retry: false) do
      {:ok, %{status: s}} when s in 200..299 -> :ok
      {:ok, %{status: s}} -> {:error, "status #{s}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp format(:ok), do: "ok"
  defp format({:error, msg}), do: msg
end
