defmodule JazidaPhoenix.MiningFixtures do
  alias JazidaPhoenix.Mining.{
    AreaAvailability,
    Fingerprint,
    MiningProcess,
    ProcessChange,
    SourceImport
  }

  alias JazidaPhoenix.Repo

  def mining_process_fixture(attrs \\ %{}) do
    unique = System.unique_integer([:positive]) |> rem(900_000) |> Kernel.+(100_000)
    number = Map.get(attrs, :number, unique)
    year = Map.get(attrs, :year, 2026)

    defaults = %{
      process_number: "#{String.pad_leading(to_string(number), 6, "0")}/#{year}",
      number: number,
      year: year,
      state_code: "PA",
      municipalities: ["PARAUAPEBAS"],
      substances: ["MINÉRIO DE FERRO"],
      area_ha: Decimal.new("125.50")
    }

    %MiningProcess{}
    |> MiningProcess.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def availability_fixture(process, attrs \\ %{}) do
    material = %{
      status: Map.get(attrs, :display_category, "eligible"),
      unique: System.unique_integer([:positive])
    }

    defaults = %{
      display_category: "eligible",
      stock_status_raw: "Apta para Disponibilidade",
      source_observed_at: DateTime.utc_now(:second),
      material_fingerprint: Fingerprint.of(material)
    }

    %AreaAvailability{mining_process_id: process.id}
    |> AreaAvailability.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def source_import_fixture(attrs \\ %{}) do
    defaults = %{
      source: "sople_stock",
      source_url: "https://anm.test/source.csv",
      status: "succeeded",
      started_at: DateTime.utc_now(:second),
      finished_at: DateTime.utc_now(:second),
      checksum_sha256: Fingerprint.of(System.unique_integer([:positive]))
    }

    %SourceImport{} |> SourceImport.changeset(Map.merge(defaults, attrs)) |> Repo.insert!()
  end

  def process_change_fixture(process, source_import, attrs \\ %{}) do
    defaults = %{
      field: "availability",
      old_value: %{"fingerprint" => "old"},
      new_value: %{"fingerprint" => "new"},
      observed_at: DateTime.utc_now(:second),
      fingerprint: Fingerprint.of(System.unique_integer([:positive]))
    }

    %ProcessChange{mining_process_id: process.id, source_import_id: source_import.id}
    |> ProcessChange.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
