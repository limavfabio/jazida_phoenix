defmodule JazidaPhoenix.Mining.RoundArea do
  use Ecto.Schema
  import Ecto.Changeset

  schema "round_areas" do
    field :area_number, :integer
    field :modality, :string
    field :availability_regime, :string
    field :situation_raw, :string
    field :display_category, :string
    field :winning_bid_brl, :decimal
    field :source_observed_at, :utc_datetime
    field :material_fingerprint, :string

    belongs_to :round, JazidaPhoenix.Mining.Round
    belongs_to :mining_process, JazidaPhoenix.Mining.MiningProcess
    timestamps(type: :utc_datetime)
  end

  def changeset(area, attrs) do
    area
    |> cast(attrs, [
      :area_number,
      :modality,
      :availability_regime,
      :situation_raw,
      :display_category,
      :winning_bid_brl,
      :source_observed_at,
      :material_fingerprint
    ])
    |> validate_required([
      :area_number,
      :modality,
      :situation_raw,
      :display_category,
      :source_observed_at,
      :material_fingerprint
    ])
    |> validate_number(:area_number, greater_than: 0)
    |> assoc_constraint(:round)
    |> assoc_constraint(:mining_process)
    |> unique_constraint([:round_id, :area_number, :modality, :situation_raw],
      name: :round_areas_source_identity_index
    )
    |> check_constraint(:area_number, name: :round_areas_area_number_positive)
  end
end
