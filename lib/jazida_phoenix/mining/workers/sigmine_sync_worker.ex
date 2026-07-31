defmodule JazidaPhoenix.Mining.Workers.SigmineSyncWorker do
  use Oban.Worker,
    queue: :imports,
    max_attempts: 3,
    unique: [period: 24 * 60 * 60, states: :incomplete]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case JazidaPhoenix.Mining.Sync.sigmine() do
      {:ok, _audit} -> :ok
      {:error, reason} -> {:error, inspect(reason)}
    end
  end
end
