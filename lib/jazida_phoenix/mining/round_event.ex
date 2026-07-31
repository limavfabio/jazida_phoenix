defmodule JazidaPhoenix.Mining.RoundEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "round_events" do
    field :slug, :string
    field :name, :string
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :official_label, :string
    field :source_reference, :string

    belongs_to :round, JazidaPhoenix.Mining.Round
    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:slug, :name, :starts_at, :ends_at, :official_label, :source_reference])
    |> validate_required([:slug, :name])
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    |> assoc_constraint(:round)
    |> unique_constraint([:round_id, :slug])
    |> check_constraint(:starts_at, name: :round_events_chronological)
  end
end
