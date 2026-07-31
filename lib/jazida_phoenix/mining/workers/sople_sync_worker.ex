defmodule JazidaPhoenix.Mining.Workers.SopleSyncWorker do
  use Oban.Worker,
    queue: :imports,
    max_attempts: 5,
    unique: [period: 6 * 60 * 60, states: :incomplete]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case JazidaPhoenix.Mining.Sync.sople() do
      {:ok, _audits} -> :ok
      {:error, reason} -> {:error, inspect(reason)}
    end
  end
end
