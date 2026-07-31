defmodule JazidaPhoenix.MiningTest do
  use JazidaPhoenix.DataCase, async: true

  alias JazidaPhoenix.Mining
  alias JazidaPhoenix.Mining.{Fingerprint, Round, RoundArea}
  alias JazidaPhoenix.Repo
  import JazidaPhoenix.MiningFixtures

  test "searches and filters the catalog while bounding result counts" do
    iron =
      mining_process_fixture(%{
        state_code: "PA",
        municipalities: ["PARAUAPEBAS"],
        substances: ["FERRO"]
      })

    _gold =
      mining_process_fixture(%{
        state_code: "MG",
        municipalities: ["OURO PRETO"],
        substances: ["OURO"]
      })

    availability_fixture(iron, %{
      display_category: "eligible",
      latest_edital_status_raw: "Habilitada para leilão",
      availability_regime: "Autorização de Pesquisa"
    })

    round = Repo.get_by!(Round, number: 8)

    %RoundArea{round_id: round.id, mining_process_id: iron.id}
    |> RoundArea.changeset(%{
      area_number: 1,
      modality: "Leilão",
      situation_raw: "Habilitada",
      display_category: "eligible",
      source_observed_at: DateTime.utc_now(:second),
      material_fingerprint: Fingerprint.of("round-area")
    })
    |> Repo.insert!()

    assert [result] =
             Mining.list_processes(%{
               "q" => "Parauapebas",
               "state" => "pa",
               "category" => "eligible",
               "municipality" => "paraua",
               "substance" => "ferro",
               "status" => "leilão",
               "regime" => "pesquisa",
               "round" => "8"
             })

    assert result.id == iron.id
    all_results = Mining.list_processes(%{"limit" => "1000"})
    assert length(all_results) == 2

    assert Enum.map(all_results, & &1.process_number) ==
             Enum.sort(Enum.map(all_results, & &1.process_number))

    assert Mining.list_processes(%{"q" => "%_"}) == []
  end

  test "freshness advances only from successful or unchanged imports" do
    now = ~U[2026-07-29 12:00:00Z]
    source_import_fixture(%{source: "sigmine", status: "failed", finished_at: now})
    assert Mining.stale?("sigmine", now)

    source_import_fixture(%{source: "sigmine", status: "succeeded", finished_at: now})
    refute Mining.stale?("sigmine", DateTime.add(now, 47, :hour))
    assert Mining.stale?("sigmine", DateTime.add(now, 49, :hour))
  end
end
