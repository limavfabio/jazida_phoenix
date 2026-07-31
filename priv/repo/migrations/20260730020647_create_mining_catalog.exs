defmodule JazidaPhoenix.Repo.Migrations.CreateMiningCatalog do
  use Ecto.Migration

  def change do
    create table(:mining_processes) do
      add :process_number, :string, null: false
      add :number, :integer, null: false
      add :year, :integer, null: false
      add :state_code, :string
      add :municipalities, {:array, :string}, null: false, default: []
      add :area_ha, :decimal, precision: 18, scale: 8
      add :phase, :string
      add :last_event, :string
      add :substances, {:array, :string}, null: false, default: []
      add :substance_uses, {:array, :string}, null: false, default: []
      add :geometry_source_observed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    execute(
      "ALTER TABLE mining_processes ADD COLUMN geometry geometry(MultiPolygon, 4674)",
      "ALTER TABLE mining_processes DROP COLUMN geometry"
    )

    create unique_index(:mining_processes, [:process_number])
    create index(:mining_processes, [:state_code])
    create index(:mining_processes, [:municipalities], using: :gin)
    create index(:mining_processes, [:substances], using: :gin)
    create index(:mining_processes, [:geometry], using: :gist)

    create constraint(:mining_processes, :mining_processes_process_number_format,
             check: "process_number ~ '^[0-9]{6}/[0-9]{4}$'"
           )

    create constraint(:mining_processes, :mining_processes_number_range,
             check: "number BETWEEN 0 AND 999999"
           )

    create constraint(:mining_processes, :mining_processes_year_range,
             check: "year BETWEEN 1900 AND 2200"
           )

    create constraint(:mining_processes, :mining_processes_area_non_negative,
             check: "area_ha IS NULL OR area_ha >= 0"
           )

    create table(:area_availabilities) do
      add :mining_process_id, references(:mining_processes, on_delete: :delete_all), null: false

      add :availability_regime, :string
      add :stock_status_raw, :string
      add :latest_edital_status_raw, :string
      add :display_category, :string, null: false
      add :nominated, :boolean, null: false, default: false
      add :listed_in_edital, :boolean, null: false, default: false
      add :source_observed_at, :utc_datetime, null: false
      add :material_fingerprint, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:area_availabilities, [:mining_process_id])
    create index(:area_availabilities, [:display_category])
    create index(:area_availabilities, [:stock_status_raw])
    create index(:area_availabilities, [:latest_edital_status_raw])

    create table(:rounds) do
      add :number, :integer, null: false
      add :title, :string, null: false
      add :official_process_number, :string
      add :notice_url, :string
      add :source_url, :string
      add :status, :string
      add :timezone, :string, null: false, default: "America/Sao_Paulo"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:rounds, [:number])
    create constraint(:rounds, :rounds_number_positive, check: "number > 0")

    create table(:round_events) do
      add :round_id, references(:rounds, on_delete: :delete_all), null: false
      add :slug, :string, null: false
      add :name, :string, null: false
      add :starts_at, :utc_datetime
      add :ends_at, :utc_datetime
      add :official_label, :string
      add :source_reference, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:round_events, [:round_id, :slug])

    create constraint(:round_events, :round_events_chronological,
             check: "starts_at IS NULL OR ends_at IS NULL OR starts_at <= ends_at"
           )

    create table(:round_areas) do
      add :round_id, references(:rounds, on_delete: :delete_all), null: false
      add :mining_process_id, references(:mining_processes, on_delete: :restrict), null: false
      add :area_number, :integer, null: false
      add :modality, :string, null: false
      add :availability_regime, :string
      add :situation_raw, :string, null: false
      add :display_category, :string, null: false
      add :winning_bid_brl, :decimal, precision: 18, scale: 2
      add :source_observed_at, :utc_datetime, null: false
      add :material_fingerprint, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:round_areas, [:round_id, :area_number, :modality, :situation_raw],
             name: :round_areas_source_identity_index
           )

    create index(:round_areas, [:mining_process_id])
    create index(:round_areas, [:display_category])
    create constraint(:round_areas, :round_areas_area_number_positive, check: "area_number > 0")

    create table(:source_imports) do
      add :source, :string, null: false
      add :source_url, :string, null: false
      add :status, :string, null: false
      add :started_at, :utc_datetime, null: false
      add :finished_at, :utc_datetime
      add :source_modified_at, :utc_datetime
      add :checksum_sha256, :string
      add :byte_size, :bigint
      add :parsed_rows, :integer, null: false, default: 0
      add :imported_rows, :integer, null: false, default: 0
      add :skipped_rows, :integer, null: false, default: 0
      add :warning_count, :integer, null: false, default: 0
      add :warnings, :map, null: false, default: %{}
      add :error_summary, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:source_imports, [:source, :status, :finished_at])
    create index(:source_imports, [:checksum_sha256])

    create constraint(:source_imports, :source_imports_status,
             check: "status IN ('running', 'succeeded', 'failed', 'unchanged')"
           )

    create constraint(:source_imports, :source_imports_counts_non_negative,
             check:
               "parsed_rows >= 0 AND imported_rows >= 0 AND skipped_rows >= 0 AND warning_count >= 0"
           )

    create table(:process_changes) do
      add :mining_process_id, references(:mining_processes, on_delete: :delete_all), null: false

      add :source_import_id, references(:source_imports, on_delete: :restrict), null: false
      add :field, :string, null: false
      add :old_value, :map
      add :new_value, :map
      add :observed_at, :utc_datetime, null: false
      add :fingerprint, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:process_changes, [:fingerprint])
    create index(:process_changes, [:mining_process_id, :observed_at])
    create index(:process_changes, [:source_import_id])
  end
end
