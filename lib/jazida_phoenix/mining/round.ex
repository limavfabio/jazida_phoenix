defmodule JazidaPhoenix.Mining.Round do
  use Ecto.Schema
  import Ecto.Changeset

  schema "rounds" do
    field :number, :integer
    field :title, :string
    field :official_process_number, :string
    field :notice_url, :string
    field :source_url, :string
    field :status, :string
    field :timezone, :string, default: "America/Sao_Paulo"

    has_many :events, JazidaPhoenix.Mining.RoundEvent
    has_many :areas, JazidaPhoenix.Mining.RoundArea
    timestamps(type: :utc_datetime)
  end

  def changeset(round, attrs) do
    round
    |> cast(attrs, [
      :number,
      :title,
      :official_process_number,
      :notice_url,
      :source_url,
      :status,
      :timezone
    ])
    |> validate_required([:number, :title, :timezone])
    |> validate_number(:number, greater_than: 0)
    |> unique_constraint(:number)
    |> check_constraint(:number, name: :rounds_number_positive)
  end
end
