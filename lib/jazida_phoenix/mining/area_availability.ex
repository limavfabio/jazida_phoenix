defmodule JazidaPhoenix.Mining.AreaAvailability do
  use Ecto.Schema
  import Ecto.Changeset

  schema "area_availabilities" do
    field :availability_regime, :string
    field :stock_status_raw, :string
    field :latest_edital_status_raw, :string
    field :display_category, :string
    field :nominated, :boolean, default: false
    field :listed_in_edital, :boolean, default: false
    field :source_observed_at, :utc_datetime
    field :material_fingerprint, :string

    belongs_to :mining_process, JazidaPhoenix.Mining.MiningProcess
    timestamps(type: :utc_datetime)
  end

  def changeset(availability, attrs) do
    availability
    |> cast(attrs, [
      :availability_regime,
      :stock_status_raw,
      :latest_edital_status_raw,
      :display_category,
      :nominated,
      :listed_in_edital,
      :source_observed_at,
      :material_fingerprint
    ])
    |> validate_required([:display_category, :source_observed_at, :material_fingerprint])
    |> assoc_constraint(:mining_process)
    |> unique_constraint(:mining_process_id)
  end
end
