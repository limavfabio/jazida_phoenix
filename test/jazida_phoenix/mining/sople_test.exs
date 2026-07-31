defmodule JazidaPhoenix.Mining.SopleTest do
  use JazidaPhoenix.DataCase, async: false

  alias JazidaPhoenix.Mining.{AreaAvailability, MiningProcess, ProcessChange, Sople, SourceImport}

  @fixture Path.expand("../../support/fixtures/anm/sople_stock.csv", __DIR__)

  test "imports transactionally, records warnings and changes, and recognizes unchanged reruns" do
    assert {:ok, first} = Sople.import_stock(@fixture, observed_at: ~U[2026-07-29 12:00:00Z])
    assert first.status == "succeeded"
    assert first.parsed_rows == 4
    assert first.imported_rows == 3
    assert first.skipped_rows == 1
    assert first.warning_count == 1
    assert Repo.aggregate(MiningProcess, :count) == 3
    assert Repo.aggregate(AreaAvailability, :count) == 3
    assert Repo.aggregate(ProcessChange, :count) == 3

    assert {:ok, second} = Sople.import_stock(@fixture, observed_at: ~U[2026-07-30 12:00:00Z])
    assert second.status == "unchanged"
    assert Repo.aggregate(ProcessChange, :count) == 3
  end

  test "a complete changed snapshot records upstream removals without deleting processes" do
    assert {:ok, _audit} = Sople.import_stock(@fixture)
    path = temporary_csv!(fn body -> String.replace(body, ~r/^300091\/2020;.*\n/m, "") end)

    assert {:ok, audit} = Sople.import_stock(path)
    assert audit.status == "succeeded"
    assert Repo.aggregate(MiningProcess, :count) == 3
    assert Repo.aggregate(AreaAvailability, :count) == 2

    assert Repo.exists?(
             from change in ProcessChange, where: change.field == "availability_removed"
           )
  end

  test "a changed snapshot applies additions and material updates exactly once" do
    assert {:ok, _audit} = Sople.import_stock(@fixture)

    path =
      temporary_csv!(fn body ->
        body
        |> String.replace(
          "300091/2020;Minas Gerais;GOUVEIA;10,13;Não se aplica;Não se aplica;;Sim;Disponibilidade;Inativo;Apta para Disponibilidade;Sim;Não Requerida",
          "300091/2020;Minas Gerais;GOUVEIA;10,13;Não se aplica;Não se aplica;;Sim;Disponibilidade;Inativo;Para Análise;Sim;Não Requerida"
        )
        |> Kernel.<>(
          "555001/2026;Pará;ITAITUBA;9,50;OURO;Industrial;Autorização de Pesquisa;Não;Disponibilidade;Inativo;Apta para Disponibilidade;Não;\n"
        )
      end)

    assert {:ok, audit} = Sople.import_stock(path)
    assert audit.imported_rows == 4
    assert Repo.aggregate(MiningProcess, :count) == 4
    assert Repo.aggregate(ProcessChange, :count) == 5

    process = Repo.get_by!(MiningProcess, process_number: "300091/2020")
    availability = Repo.get_by!(AreaAvailability, mining_process_id: process.id)
    assert availability.stock_status_raw == "Para Análise"
  end

  test "database constraint failure rolls back catalog writes and leaves a failed audit" do
    assert {:ok, successful} = Sople.import_stock(@fixture)
    oversized_phase = String.duplicate("A", 300)

    path =
      temporary_csv!(fn body ->
        String.replace(body, "Licenciamento", oversized_phase, global: false)
      end)

    assert {:error, failed} = Sople.import_stock(path)
    assert failed.status == "failed"
    assert Repo.aggregate(MiningProcess, :count) == 3
    assert Repo.aggregate(AreaAvailability, :count) == 3
    assert JazidaPhoenix.Mining.latest_successful_import("sople_stock").id == successful.id

    assert Repo.aggregate(
             from(audit in SourceImport, where: audit.source == "sople_stock"),
             :count
           ) ==
             2

    assert is_binary(failed.error_summary)
  end

  defp temporary_csv!(transform) do
    path =
      Path.join(System.tmp_dir!(), "jazida-sople-test-#{System.unique_integer([:positive])}.csv")

    File.write!(path, @fixture |> File.read!() |> transform.())
    on_exit(fn -> File.rm(path) end)
    path
  end
end
