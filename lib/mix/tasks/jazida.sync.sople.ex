defmodule Mix.Tasks.Jazida.Sync.Sople do
  use Mix.Task

  @shortdoc "Synchronizes the official SOPLE stock and round-result sources"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    case JazidaPhoenix.Mining.Sync.sople() do
      {:ok, audits} -> Mix.shell().info("SOPLE synchronization completed: #{inspect(audits)}")
      {:error, reason} -> Mix.raise("SOPLE synchronization failed: #{inspect(reason)}")
    end
  end
end
