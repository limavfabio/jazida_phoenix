defmodule JazidaPhoenix.Mining.SourceImport do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(running succeeded failed unchanged)

  schema "source_imports" do
    field :source, :string
    field :source_url, :string
    field :status, :string
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :source_modified_at, :utc_datetime
    field :checksum_sha256, :string
    field :byte_size, :integer
    field :parsed_rows, :integer, default: 0
    field :imported_rows, :integer, default: 0
    field :skipped_rows, :integer, default: 0
    field :warning_count, :integer, default: 0
    field :warnings, :map, default: %{}
    field :error_summary, :string

    has_many :changes, JazidaPhoenix.Mining.ProcessChange
    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(source_import, attrs) do
    source_import
    |> cast(attrs, [
      :source,
      :source_url,
      :status,
      :started_at,
      :finished_at,
      :source_modified_at,
      :checksum_sha256,
      :byte_size,
      :parsed_rows,
      :imported_rows,
      :skipped_rows,
      :warning_count,
      :warnings,
      :error_summary
    ])
    |> validate_required([:source, :source_url, :status, :started_at])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:byte_size, greater_than_or_equal_to: 0)
    |> validate_counts()
    |> check_constraint(:status, name: :source_imports_status)
    |> check_constraint(:parsed_rows, name: :source_imports_counts_non_negative)
  end

  defp validate_counts(changeset) do
    Enum.reduce(
      [:parsed_rows, :imported_rows, :skipped_rows, :warning_count],
      changeset,
      fn field, acc ->
        validate_number(acc, field, greater_than_or_equal_to: 0)
      end
    )
  end
end
