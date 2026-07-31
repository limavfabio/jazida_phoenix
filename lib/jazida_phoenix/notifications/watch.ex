defmodule JazidaPhoenix.Notifications.Watch do
  use Ecto.Schema
  import Ecto.Changeset

  schema "watches" do
    field :active, :boolean, default: true
    belongs_to :user, JazidaPhoenix.Accounts.User
    belongs_to :mining_process, JazidaPhoenix.Mining.MiningProcess
    timestamps(type: :utc_datetime)
  end

  def changeset(watch, attrs) do
    watch
    |> cast(attrs, [:active])
    |> assoc_constraint(:user)
    |> assoc_constraint(:mining_process)
    |> unique_constraint([:user_id, :mining_process_id])
  end
end
