defmodule JazidaPhoenix.Mining.Sigmine do
  @moduledoc "Audited SIGMINE geometry import through bounded archives and GDAL staging."

  import Ecto.Query
  require Logger

  alias JazidaPhoenix.Mining.{Archive, Fingerprint, ProcessChange, SourceImport}
  alias JazidaPhoenix.Repo

  @source "sigmine"

  def import_archives(active_archive, inactive_archive, opts \\ []) do
    observed_at =
      Keyword.get_lazy(opts, :observed_at, &DateTime.utc_now/0) |> DateTime.truncate(:second)

    started_at = DateTime.utc_now(:second)

    checksum =
      Fingerprint.of(%{active: sha256(active_archive), inactive: sha256(inactive_archive)})

    byte_size = File.stat!(active_archive).size + File.stat!(inactive_archive).size
    source_url = Keyword.get(opts, :source_url, "ANM SIGMINE active+inactive")

    with {:ok, audit} <-
           start_audit(source_url, started_at, observed_at, checksum, byte_size) do
      if unchanged_since_last_reconciliation?(checksum, audit.id) do
        finish_unchanged(audit)
      else
        run_import(audit, active_archive, inactive_archive, observed_at)
      end
    end
  end

  defp run_import(audit, active_archive, inactive_archive, now) do
    directory = temporary_directory!()
    suffix = System.unique_integer([:positive, :monotonic])
    active_table = "sigmine_active_#{suffix}"
    inactive_table = "sigmine_inactive_#{suffix}"

    result =
      try do
        with {:ok, active_shape} <-
               Archive.extract_sigmine(active_archive, Path.join(directory, "active")),
             {:ok, inactive_shape} <-
               Archive.extract_sigmine(inactive_archive, Path.join(directory, "inactive")),
             :ok <- load_stage(active_shape, active_table),
             :ok <- load_stage(inactive_shape, inactive_table) do
          persist_geometry(audit, active_table, inactive_table, now)
        end
      rescue
        exception -> {:error, exception}
      after
        drop_stage(active_table)
        drop_stage(inactive_table)
        File.rm_rf(directory)
      end

    case result do
      {:ok, updated} ->
        JazidaPhoenix.Notifications.materialize(updated.id)
        log_outcome(updated)
        {:ok, updated}

      {:error, reason} ->
        fail_audit(audit, reason)
    end
  end

  defp load_stage(shape_path, table) do
    args = [
      "-f",
      "PostgreSQL",
      postgres_connection(),
      shape_path,
      "-nln",
      table,
      "-overwrite",
      "-lco",
      "GEOMETRY_NAME=geometry",
      "-nlt",
      "PROMOTE_TO_MULTI",
      "-dim",
      "XY",
      "-t_srs",
      "EPSG:4674"
    ]

    with :ok <- validate_source_with_ogrinfo(shape_path) do
      case System.cmd("ogr2ogr", args, stderr_to_stdout: true, env: postgres_environment()) do
        {_output, 0} -> validate_stage(table)
        {output, status} -> {:error, {:gdal_failed, status, String.slice(output, 0, 1_000)}}
      end
    end
  rescue
    error in ErlangError -> {:error, {:gdal_unavailable, Exception.message(error)}}
  end

  defp validate_stage(table) do
    %{rows: column_rows} =
      Repo.query!(
        "SELECT column_name FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = $1",
        [table]
      )

    columns = MapSet.new(column_rows, fn [column] -> column end)

    unless MapSet.subset?(MapSet.new(~w(processo dsprocesso geometry)), columns) do
      raise "SIGMINE stage is missing required source attributes"
    end

    sql =
      "SELECT count(*), count(*) FILTER (WHERE ST_SRID(geometry) <> 4674), count(*) FILTER (WHERE GeometryType(geometry) NOT IN ('POLYGON', 'MULTIPOLYGON')) FROM \"#{table}\""

    %{rows: [[count, wrong_srid, wrong_type]]} = Repo.query!(sql)

    cond do
      count == 0 -> {:error, :empty_geometry_source}
      wrong_srid > 0 -> {:error, {:unexpected_srid, wrong_srid}}
      wrong_type > 0 -> {:error, {:unexpected_geometry_type, wrong_type}}
      true -> :ok
    end
  end

  defp validate_source_with_ogrinfo(shape_path) do
    case System.cmd("ogrinfo", ["-ro", "-so", "-al", shape_path], stderr_to_stdout: true) do
      {output, 0} ->
        cond do
          not String.contains?(output, ~s(ID["EPSG",4674])) ->
            {:error, :unexpected_source_srid}

          not (String.contains?(output, "Geometry: Polygon") or
                 String.contains?(output, "Geometry: Multi Polygon") or
                   String.contains?(output, "Geometry: 3D Measured Polygon")) ->
            {:error, :unexpected_source_geometry_type}

          true ->
            :ok
        end

      {output, status} ->
        {:error, {:ogrinfo_failed, status, String.slice(output, 0, 1_000)}}
    end
  rescue
    error in ErlangError -> {:error, {:gdal_unavailable, Exception.message(error)}}
  end

  defp persist_geometry(audit, active_table, inactive_table, now) do
    Repo.transaction(
      fn ->
        before = geometry_hashes()
        %{rows: [[duplicate_count]]} = Repo.query!(duplicate_sql(active_table, inactive_table))
        %{rows: [[invalid_count]]} = Repo.query!(invalid_sql(active_table, inactive_table))
        %{rows: [[overlap_count]]} = Repo.query!(overlap_sql(active_table, inactive_table))
        duplicate_samples = diagnostic_values(duplicate_samples_sql(active_table, inactive_table))
        invalid_samples = diagnostic_values(invalid_samples_sql(active_table, inactive_table))
        overlap_samples = diagnostic_values(overlap_samples_sql(active_table, inactive_table))

        Repo.query!(clear_relevant_sql())
        %{num_rows: imported_rows} = Repo.query!(update_sql(active_table, inactive_table), [now])
        after_hashes = geometry_hashes()
        insert_geometry_changes(before, after_hashes, audit, now)

        %{rows: [[missing_count]]} = Repo.query!(missing_sql())
        missing_samples = diagnostic_values(missing_samples_sql())

        warnings = %{
          "duplicates" => %{"count" => duplicate_count, "samples" => duplicate_samples},
          "invalid_source_geometries" => %{
            "count" => invalid_count,
            "samples" => invalid_samples
          },
          "active_inactive_overlap" => %{
            "count" => overlap_count,
            "samples" => overlap_samples
          },
          "missing_relevant_geometries" => %{
            "count" => missing_count,
            "samples" => missing_samples
          }
        }

        warning_count = duplicate_count + invalid_count + missing_count

        case finish_audit(audit, %{
               status: "succeeded",
               finished_at: DateTime.utc_now(:second),
               parsed_rows: stage_count(active_table) + stage_count(inactive_table),
               imported_rows: imported_rows,
               warning_count: warning_count,
               warnings: warnings
             }) do
          {:ok, updated} -> updated
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end,
      timeout: :infinity
    )
  end

  defp geometry_hashes do
    sql = """
    SELECT p.id, md5(ST_AsEWKB(p.geometry))
    FROM mining_processes p
    WHERE EXISTS (SELECT 1 FROM area_availabilities a WHERE a.mining_process_id = p.id)
       OR EXISTS (SELECT 1 FROM round_areas r WHERE r.mining_process_id = p.id)
    """

    Repo.query!(sql).rows |> Map.new(fn [id, hash] -> {id, hash} end)
  end

  defp insert_geometry_changes(before, after_hashes, audit, now) do
    rows =
      after_hashes
      |> Enum.filter(fn {id, hash} -> Map.get(before, id) != hash end)
      |> Enum.map(fn {id, hash} ->
        old = Map.get(before, id)

        %{
          mining_process_id: id,
          source_import_id: audit.id,
          field: "geometry",
          old_value: value_map(old),
          new_value: value_map(hash),
          observed_at: now,
          fingerprint:
            Fingerprint.of(%{
              process: id,
              field: "geometry",
              old: old,
              new: hash,
              source_checksum: audit.checksum_sha256
            }),
          inserted_at: now
        }
      end)

    rows
    |> Enum.chunk_every(2_000)
    |> Enum.each(&Repo.insert_all(ProcessChange, &1, on_conflict: :nothing))
  end

  defp update_sql(active, inactive) do
    """
    WITH source_rows AS (
      SELECT 0 AS priority, processo, dsprocesso, geometry FROM "#{active}"
      UNION ALL
      SELECT 1 AS priority, processo, dsprocesso, geometry FROM "#{inactive}"
    ), normalized AS (
      SELECT priority,
             CASE WHEN btrim(processo) ~ '^\\d{1,6}/\\d{4}$'
                  THEN lpad(split_part(btrim(processo), '/', 1), 6, '0') || '/' || split_part(btrim(processo), '/', 2)
                  WHEN btrim(dsprocesso) ~ '^\\d{1,3}\\.\\d{3}/\\d{4}$'
                  THEN replace(split_part(btrim(dsprocesso), '/', 1), '.', '') || '/' || split_part(btrim(dsprocesso), '/', 2)
             END AS process_number,
             ST_CollectionExtract(ST_MakeValid(ST_Force2D(geometry)), 3) AS geometry
      FROM source_rows
    ), relevant AS (
      SELECT p.id, n.priority, n.geometry,
             min(n.priority) OVER (PARTITION BY p.id) AS chosen_priority
      FROM normalized n
      JOIN mining_processes p ON p.process_number = n.process_number
      WHERE n.process_number IS NOT NULL AND NOT ST_IsEmpty(n.geometry)
        AND (EXISTS (SELECT 1 FROM area_availabilities a WHERE a.mining_process_id = p.id)
          OR EXISTS (SELECT 1 FROM round_areas r WHERE r.mining_process_id = p.id))
    ), consolidated AS (
      SELECT id,
             ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_UnaryUnion(ST_Collect(geometry))), 3))::geometry(MultiPolygon, 4674) AS geometry
      FROM relevant
      WHERE priority = chosen_priority
      GROUP BY id
    )
    UPDATE mining_processes p
    SET geometry = c.geometry, geometry_source_observed_at = $1, updated_at = $1
    FROM consolidated c
    WHERE p.id = c.id AND c.geometry IS NOT NULL AND NOT ST_IsEmpty(c.geometry)
    """
  end

  defp clear_relevant_sql do
    """
    UPDATE mining_processes p
    SET geometry = NULL, geometry_source_observed_at = NULL
    WHERE EXISTS (SELECT 1 FROM area_availabilities a WHERE a.mining_process_id = p.id)
       OR EXISTS (SELECT 1 FROM round_areas r WHERE r.mining_process_id = p.id)
    """
  end

  defp duplicate_sql(active, inactive) do
    """
    SELECT count(*) FROM (
      SELECT processo FROM (SELECT processo FROM "#{active}" UNION ALL SELECT processo FROM "#{inactive}") s
      GROUP BY processo HAVING count(*) > 1
    ) duplicates
    """
  end

  defp invalid_sql(active, inactive) do
    "SELECT count(*) FROM (SELECT geometry FROM \"#{active}\" UNION ALL SELECT geometry FROM \"#{inactive}\") s WHERE NOT ST_IsValid(geometry)"
  end

  defp duplicate_samples_sql(active, inactive) do
    """
    SELECT processo FROM (SELECT processo FROM "#{active}" UNION ALL SELECT processo FROM "#{inactive}") s
    GROUP BY processo HAVING count(*) > 1 ORDER BY processo LIMIT 20
    """
  end

  defp invalid_samples_sql(active, inactive) do
    """
    SELECT processo FROM (SELECT processo, geometry FROM "#{active}" UNION ALL SELECT processo, geometry FROM "#{inactive}") s
    WHERE NOT ST_IsValid(geometry) ORDER BY processo LIMIT 20
    """
  end

  defp overlap_samples_sql(active, inactive) do
    """
    SELECT DISTINCT a.processo FROM "#{active}" a
    JOIN "#{inactive}" i ON i.processo = a.processo
    ORDER BY a.processo LIMIT 20
    """
  end

  defp overlap_sql(active, inactive) do
    """
    SELECT count(*) FROM (
      SELECT DISTINCT a.processo FROM "#{active}" a JOIN "#{inactive}" i ON i.processo = a.processo
    ) overlap_rows
    """
  end

  defp missing_sql do
    """
    SELECT count(*) FROM mining_processes p
    WHERE p.geometry IS NULL AND (
      EXISTS (SELECT 1 FROM area_availabilities a WHERE a.mining_process_id = p.id)
      OR EXISTS (SELECT 1 FROM round_areas r WHERE r.mining_process_id = p.id)
    )
    """
  end

  defp missing_samples_sql do
    """
    SELECT p.process_number FROM mining_processes p
    WHERE p.geometry IS NULL AND (
      EXISTS (SELECT 1 FROM area_availabilities a WHERE a.mining_process_id = p.id)
      OR EXISTS (SELECT 1 FROM round_areas r WHERE r.mining_process_id = p.id)
    ) ORDER BY p.process_number LIMIT 20
    """
  end

  defp diagnostic_values(sql), do: Repo.query!(sql).rows |> Enum.map(&hd/1)

  defp stage_count(table) do
    %{rows: [[count]]} = Repo.query!("SELECT count(*) FROM \"#{table}\"")
    count
  end

  defp start_audit(source_url, started_at, observed_at, checksum, byte_size) do
    %SourceImport{}
    |> SourceImport.changeset(%{
      source: @source,
      source_url: source_url,
      status: "running",
      started_at: started_at,
      source_modified_at: observed_at,
      checksum_sha256: checksum,
      byte_size: byte_size
    })
    |> Repo.insert()
  end

  defp unchanged_since_last_reconciliation?(checksum, current_id) do
    previous =
      SourceImport
      |> where(
        [audit],
        audit.source == @source and audit.id != ^current_id and audit.status == "succeeded"
      )
      |> order_by([audit], desc: audit.finished_at)
      |> limit(1)
      |> Repo.one()

    case previous do
      %{checksum_sha256: ^checksum, finished_at: finished_at} ->
        not relevant_source_advanced_after?(finished_at)

      _ ->
        false
    end
  end

  defp relevant_source_advanced_after?(finished_at) do
    SourceImport
    |> where(
      [audit],
      audit.source in ["sople_stock", "sople_round_results"] and
        audit.status == "succeeded" and audit.finished_at > ^finished_at
    )
    |> Repo.exists?()
  end

  defp finish_audit(audit, attrs), do: audit |> SourceImport.changeset(attrs) |> Repo.update()

  defp finish_unchanged(audit) do
    case finish_audit(audit, %{status: "unchanged", finished_at: DateTime.utc_now(:second)}) do
      {:ok, updated} ->
        log_outcome(updated)
        {:ok, updated}

      error ->
        error
    end
  end

  defp fail_audit(audit, reason) do
    summary =
      if is_exception(reason),
        do: Exception.message(reason),
        else: inspect(reason, printable_limit: 500)

    case finish_audit(audit, %{
           status: "failed",
           finished_at: DateTime.utc_now(:second),
           error_summary: String.slice(summary, 0, 240)
         }) do
      {:ok, failed} ->
        log_outcome(failed)
        {:error, failed}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp log_outcome(audit) do
    Logger.info("source import finished",
      source: audit.source,
      source_import_id: audit.id,
      outcome: audit.status,
      parsed_rows: audit.parsed_rows,
      imported_rows: audit.imported_rows,
      warning_count: audit.warning_count,
      duration_ms: max(DateTime.diff(audit.finished_at, audit.started_at, :millisecond), 0)
    )
  end

  defp drop_stage(table), do: Repo.query("DROP TABLE IF EXISTS \"#{table}\"")

  defp postgres_connection do
    config = Repo.config()
    host = config[:socket_dir] || config[:hostname] || "localhost"
    port = config[:port] || 5432

    "PG:dbname=#{quote_connection(config[:database])} user=#{quote_connection(config[:username])} host=#{quote_connection(host)} port=#{port}"
  end

  defp postgres_environment do
    case Repo.config()[:password] do
      password when is_binary(password) -> [{"PGPASSWORD", password}]
      _ -> []
    end
  end

  defp quote_connection(value),
    do: "'#{value |> to_string() |> String.replace("\\", "\\\\") |> String.replace("'", "\\'")}'"

  defp temporary_directory! do
    path =
      Path.join(
        System.tmp_dir!(),
        "jazida-sigmine-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(path)
    path
  end

  defp value_map(nil), do: nil
  defp value_map(value), do: %{"fingerprint" => value}

  defp sha256(path) do
    path
    |> File.stream!(64 * 1024, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end
end
