defmodule JazidaPhoenix.Mining.ProcessChange do
  use Ecto.Schema
  import Ecto.Changeset

  schema "process_changes" do
    field :field, :string
    field :old_value, :map
    field :new_value, :map
    field :observed_at, :utc_datetime
    field :fingerprint, :string

    belongs_to :mining_process, JazidaPhoenix.Mining.MiningProcess
    belongs_to :source_import, JazidaPhoenix.Mining.SourceImport
    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(change, attrs) do
    change
    |> cast(attrs, [:field, :old_value, :new_value, :observed_at, :fingerprint])
    |> validate_required([:field, :observed_at, :fingerprint])
    |> assoc_constraint(:mining_process)
    |> assoc_constraint(:source_import)
    |> unique_constraint(:fingerprint)
  end
end
