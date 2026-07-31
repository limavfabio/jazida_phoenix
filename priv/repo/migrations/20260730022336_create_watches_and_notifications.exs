defmodule JazidaPhoenix.Repo.Migrations.CreateWatchesAndNotifications do
  use Ecto.Migration

  def change do
    create table(:watches) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :mining_process_id, references(:mining_processes, on_delete: :delete_all), null: false
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:watches, [:user_id, :mining_process_id])
    create index(:watches, [:mining_process_id], where: "active")

    create table(:notifications) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :mining_process_id, references(:mining_processes, on_delete: :delete_all), null: false
      add :process_change_id, references(:process_changes, on_delete: :delete_all), null: false
      add :read_at, :utc_datetime
      add :digest_date, :date
      add :delivered_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:notifications, [:user_id, :process_change_id])
    create index(:notifications, [:user_id, :read_at, :inserted_at])
    create index(:notifications, [:digest_date, :delivered_at])

    create table(:digests) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :calendar_date, :date, null: false
      add :status, :string, null: false
      add :notification_count, :integer, null: false, default: 0
      add :sent_at, :utc_datetime
      add :error_summary, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:digests, [:user_id, :calendar_date])
    create constraint(:digests, :digests_status, check: "status IN ('pending', 'sent', 'failed')")

    create constraint(:digests, :digests_notification_count_non_negative,
             check: "notification_count >= 0"
           )
  end
end
