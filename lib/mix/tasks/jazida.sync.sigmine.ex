defmodule Mix.Tasks.Jazida.Sync.Sigmine do
  use Mix.Task

  @shortdoc "Synchronizes official active and inactive SIGMINE geometry"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    case JazidaPhoenix.Mining.Sync.sigmine() do
      {:ok, audit} -> Mix.shell().info("SIGMINE synchronization completed: #{inspect(audit)}")
      {:error, reason} -> Mix.raise("SIGMINE synchronization failed: #{inspect(reason)}")
    end
  end
end
