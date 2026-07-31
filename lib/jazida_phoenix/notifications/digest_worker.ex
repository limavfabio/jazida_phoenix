defmodule JazidaPhoenix.Notifications.DigestWorker do
  use Oban.Worker,
    queue: :notifications,
    max_attempts: 5,
    unique: [period: 23 * 60 * 60, states: :incomplete]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    JazidaPhoenix.Notifications.deliver_daily_digests()
  end
end
