defmodule JazidaPhoenix.Mining.MiningProcess do
  use Ecto.Schema
  import Ecto.Changeset

  schema "mining_processes" do
    field :process_number, :string
    field :number, :integer
    field :year, :integer
    field :state_code, :string
    field :municipalities, {:array, :string}, default: []
    field :area_ha, :decimal
    field :phase, :string
    field :last_event, :string
    field :substances, {:array, :string}, default: []
    field :substance_uses, {:array, :string}, default: []
    field :geometry, Geo.PostGIS.Geometry
    field :geometry_source_observed_at, :utc_datetime

    has_one :availability, JazidaPhoenix.Mining.AreaAvailability
    has_many :round_areas, JazidaPhoenix.Mining.RoundArea
    has_many :changes, JazidaPhoenix.Mining.ProcessChange

    timestamps(type: :utc_datetime)
  end

  def changeset(process, attrs) do
    process
    |> cast(attrs, [
      :process_number,
      :number,
      :year,
      :state_code,
      :municipalities,
      :area_ha,
      :phase,
      :last_event,
      :substances,
      :substance_uses,
      :geometry,
      :geometry_source_observed_at
    ])
    |> validate_required([:process_number, :number, :year])
    |> validate_format(:process_number, ~r/^\d{6}\/\d{4}$/)
    |> validate_number(:number, greater_than_or_equal_to: 0, less_than: 1_000_000)
    |> validate_number(:year, greater_than_or_equal_to: 1900, less_than_or_equal_to: 2200)
    |> validate_number(:area_ha, greater_than_or_equal_to: 0)
    |> unique_constraint(:process_number)
    |> check_constraint(:process_number, name: :mining_processes_process_number_format)
    |> check_constraint(:number, name: :mining_processes_number_range)
    |> check_constraint(:year, name: :mining_processes_year_range)
    |> check_constraint(:area_ha, name: :mining_processes_area_non_negative)
  end
end
