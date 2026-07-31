defmodule JazidaPhoenix.Mining.SigmineTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias JazidaPhoenix.Mining.{
    AreaAvailability,
    MiningProcess,
    ProcessChange,
    Sigmine,
    Sople,
    SourceImport
  }

  alias JazidaPhoenix.Repo

  @stock_fixture Path.expand("../../support/fixtures/anm/sople_stock.csv", __DIR__)
  @geometry_fixture Path.expand("../../support/fixtures/anm/sigmine_processes.geojson", __DIR__)

  test "loads, repairs, consolidates, and idempotently audits representative geometry" do
    assert System.find_executable("ogr2ogr"), "ogr2ogr is required for spatial import tests"
    {active, inactive, directory} = geometry_archives!()

    try do
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        cleanup_fixture_rows()

        try do
          assert {:ok, _audit} = Sople.import_stock(@stock_fixture)

          assert {:ok, audit} = Sigmine.import_archives(active, inactive)
          assert audit.status == "succeeded"
          assert audit.imported_rows == 3
          assert audit.warnings["duplicates"]["count"] == 3

          %{rows: rows} =
            Repo.query!("""
            SELECT process_number, ST_IsValid(geometry), GeometryType(geometry), ST_SRID(geometry)
            FROM mining_processes WHERE geometry IS NOT NULL ORDER BY process_number
            """)

          assert rows == [
                   ["300091/2020", true, "MULTIPOLYGON", 4674],
                   ["811171/2016", true, "MULTIPOLYGON", 4674],
                   ["844001/2022", true, "MULTIPOLYGON", 4674]
                 ]

          assert Repo.aggregate(
                   from(change in ProcessChange, where: change.field == "geometry"),
                   :count
                 ) == 3

          assert {:ok, unchanged} = Sigmine.import_archives(active, inactive)
          assert unchanged.status == "unchanged"

          %SourceImport{}
          |> SourceImport.changeset(%{
            source: "sople_stock",
            source_url: "https://anm.test/new-stock.csv",
            status: "succeeded",
            started_at: DateTime.add(audit.finished_at, 1, :second),
            finished_at: DateTime.add(audit.finished_at, 1, :second),
            checksum_sha256: String.duplicate("a", 64)
          })
          |> Repo.insert!()

          assert {:ok, reconciled} = Sigmine.import_archives(active, inactive)
          assert reconciled.status == "succeeded"
          assert reconciled.imported_rows == 3
        after
          cleanup_fixture_rows()
        end
      end)
    after
      File.rm_rf(directory)
    end
  end

  test "unsafe archive fails audit without changing existing geometry" do
    directory =
      Path.join(System.tmp_dir!(), "jazida-sigmine-unsafe-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    archive = Path.join(directory, "unsafe.zip")
    {:ok, _} = :zip.create(String.to_charlist(archive), [{~c"../escape.shp", "unsafe"}], [])

    try do
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(from audit in SourceImport, where: audit.source == "sigmine")

        try do
          assert {:error, audit} = Sigmine.import_archives(archive, archive)
          assert audit.status == "failed"
          assert audit.error_summary =~ "unsafe_archive_path"
        after
          Repo.delete_all(from audit in SourceImport, where: audit.source == "sigmine")
        end
      end)
    after
      File.rm_rf(directory)
    end
  end

  defp geometry_archives! do
    directory =
      Path.join(System.tmp_dir!(), "jazida-sigmine-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)

    archives =
      for source <- ~w(active inactive) do
        shape_directory = Path.join(directory, source)
        File.mkdir_p!(shape_directory)
        shape = Path.join(shape_directory, "fixture.shp")

        {_output, 0} =
          System.cmd(
            "ogr2ogr",
            ["-f", "ESRI Shapefile", shape, @geometry_fixture, "-t_srs", "EPSG:4674"],
            stderr_to_stdout: true
          )

        entries =
          shape_directory
          |> File.ls!()
          |> Enum.map(fn name ->
            {String.to_charlist(name), File.read!(Path.join(shape_directory, name))}
          end)

        archive = Path.join(directory, "#{source}.zip")
        {:ok, _} = :zip.create(String.to_charlist(archive), entries, [])
        archive
      end

    {Enum.at(archives, 0), Enum.at(archives, 1), directory}
  end

  defp cleanup_fixture_rows do
    numbers = ["300091/2020", "811171/2016", "844001/2022"]

    ids =
      Repo.all(
        from process in MiningProcess,
          where: process.process_number in ^numbers,
          select: process.id
      )

    Repo.delete_all(from change in ProcessChange, where: change.mining_process_id in ^ids)

    Repo.delete_all(
      from availability in AreaAvailability, where: availability.mining_process_id in ^ids
    )

    Repo.delete_all(from process in MiningProcess, where: process.id in ^ids)
    Repo.delete_all(from audit in SourceImport, where: audit.source in ["sople_stock", "sigmine"])
  end
end
