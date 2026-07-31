defmodule JazidaPhoenix.Notifications.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  schema "notifications" do
    field :read_at, :utc_datetime
    field :digest_date, :date
    field :delivered_at, :utc_datetime
    belongs_to :user, JazidaPhoenix.Accounts.User
    belongs_to :mining_process, JazidaPhoenix.Mining.MiningProcess
    belongs_to :process_change, JazidaPhoenix.Mining.ProcessChange
    timestamps(type: :utc_datetime)
  end

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:read_at, :digest_date, :delivered_at])
    |> assoc_constraint(:user)
    |> assoc_constraint(:mining_process)
    |> assoc_constraint(:process_change)
    |> unique_constraint([:user_id, :process_change_id])
  end
end
