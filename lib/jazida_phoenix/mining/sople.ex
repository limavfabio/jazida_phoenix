defmodule JazidaPhoenix.Mining.Sople do
  @moduledoc "Transactional imports for public SOPLE stock and round-result CSV files."

  import Ecto.Query
  require Logger

  alias JazidaPhoenix.Mining.{
    AreaAvailability,
    Fingerprint,
    MiningProcess,
    ProcessChange,
    Round,
    RoundArea,
    SopleParser,
    SourceImport
  }

  alias JazidaPhoenix.Repo

  @stock_source "sople_stock"
  @round_source "sople_round_results"

  def import_stock(path, opts \\ []) do
    import_file(@stock_source, path, opts, &SopleParser.stock_rows/1, &persist_stock/3)
  end

  def import_round_results(path, opts \\ []) do
    import_file(@round_source, path, opts, &SopleParser.round_rows/1, &persist_rounds/3)
  end

  defp import_file(source, path, opts, parser, persist) do
    observed_at =
      Keyword.get_lazy(opts, :observed_at, &DateTime.utc_now/0) |> DateTime.truncate(:second)

    started_at = DateTime.utc_now(:second)
    source_url = Keyword.get(opts, :source_url, "file://#{Path.basename(path)}")

    with {:ok, stat} <- File.stat(path),
         checksum <- sha256(path),
         {:ok, audit} <-
           start_audit(source, source_url, started_at, observed_at, checksum, stat.size) do
      if previous_checksum?(source, checksum, audit.id) do
        finish_unchanged(audit)
      else
        run_import(audit, path, observed_at, parser, persist)
      end
    end
  end

  defp run_import(audit, path, observed_at, parser, persist) do
    parsed = parser.(path)
    row_warnings = Enum.flat_map(parsed.rows, &Map.get(&1, :warnings, []))
    warnings = parsed.warnings ++ row_warnings

    result =
      Repo.transaction(
        fn ->
          imported_rows = persist.(parsed.rows, audit, observed_at)

          attrs = %{
            status: "succeeded",
            finished_at: DateTime.utc_now(:second),
            parsed_rows: length(parsed.rows) + length(parsed.warnings),
            imported_rows: imported_rows,
            skipped_rows: length(parsed.warnings),
            warning_count: length(warnings),
            warnings: summarize_warnings(warnings)
          }

          case audit |> SourceImport.changeset(attrs) |> Repo.update() do
            {:ok, updated} -> updated
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end,
        timeout: :infinity
      )

    case result do
      {:ok, updated} ->
        JazidaPhoenix.Notifications.materialize(updated.id)
        log_outcome(updated)
        {:ok, updated}

      {:error, reason} ->
        fail_audit(audit, reason)
    end
  rescue
    exception -> fail_audit(audit, exception)
  catch
    kind, reason -> fail_audit(audit, {kind, reason})
  end

  defp persist_stock(rows, audit, now) do
    rows = deduplicate(rows, & &1.process.process_number)

    process_ids =
      upsert_processes(rows, now, [
        :number,
        :year,
        :state_code,
        :municipalities,
        :area_ha,
        :phase,
        :last_event,
        :substances,
        :substance_uses,
        :updated_at
      ])

    existing =
      AreaAvailability
      |> where([availability], availability.mining_process_id in ^Map.values(process_ids))
      |> select(
        [availability],
        {availability.mining_process_id, availability.material_fingerprint}
      )
      |> Repo.all()
      |> Map.new()

    availability_rows =
      Enum.map(rows, fn row ->
        row.availability
        |> Map.merge(%{
          mining_process_id: Map.fetch!(process_ids, row.process.process_number),
          source_observed_at: now,
          inserted_at: now,
          updated_at: now
        })
      end)

    insert_changes(availability_rows, existing, audit, now, "availability")

    availability_rows
    |> Enum.chunk_every(2_000)
    |> Enum.each(fn chunk ->
      Repo.insert_all(AreaAvailability, chunk,
        conflict_target: [:mining_process_id],
        on_conflict:
          {:replace,
           [
             :availability_regime,
             :stock_status_raw,
             :latest_edital_status_raw,
             :display_category,
             :nominated,
             :listed_in_edital,
             :source_observed_at,
             :material_fingerprint,
             :updated_at
           ]}
      )
    end)

    remove_missing_availability(Map.values(process_ids), existing, audit, now)
    length(rows)
  end

  defp persist_rounds(rows, audit, now) do
    rows =
      deduplicate(rows, fn row ->
        area = row.round_area
        {area.round_number, area.area_number, area.modality, area.situation_raw}
      end)

    process_ids =
      upsert_processes(rows, now, [
        :number,
        :year,
        :state_code,
        :municipalities,
        :area_ha,
        :updated_at
      ])

    round_ids =
      rows
      |> Enum.map(& &1.round_area.round_number)
      |> Enum.uniq()
      |> Enum.map(fn number ->
        attrs = %{number: number, title: "#{number}ª Rodada", inserted_at: now, updated_at: now}

        Repo.insert_all(Round, [attrs],
          conflict_target: [:number],
          on_conflict: {:replace, [:title, :updated_at]}
        )
      end)
      |> then(fn _ ->
        Round
        |> where([round], round.number in ^Enum.map(rows, & &1.round_area.round_number))
        |> select([round], {round.number, round.id})
        |> Repo.all()
        |> Map.new()
      end)

    area_rows =
      Enum.map(rows, fn row ->
        row.round_area
        |> Map.drop([:round_number])
        |> Map.merge(%{
          round_id: Map.fetch!(round_ids, row.round_area.round_number),
          mining_process_id: Map.fetch!(process_ids, row.process.process_number),
          source_observed_at: now,
          inserted_at: now,
          updated_at: now
        })
      end)

    existing =
      RoundArea
      |> where([area], area.round_id in ^Map.values(round_ids))
      |> select(
        [area],
        {{area.round_id, area.area_number, area.modality, area.situation_raw},
         area.material_fingerprint}
      )
      |> Repo.all()
      |> Map.new()

    change_rows =
      Enum.map(area_rows, fn area ->
        Map.put(
          area,
          :old_fingerprint,
          Map.get(existing, {area.round_id, area.area_number, area.modality, area.situation_raw})
        )
      end)

    insert_changes(change_rows, %{}, audit, now, "round_area")

    area_rows
    |> Enum.chunk_every(2_000)
    |> Enum.each(fn chunk ->
      Repo.insert_all(RoundArea, chunk,
        conflict_target: [:round_id, :area_number, :modality, :situation_raw],
        on_conflict:
          {:replace,
           [
             :mining_process_id,
             :availability_regime,
             :display_category,
             :winning_bid_brl,
             :source_observed_at,
             :material_fingerprint,
             :updated_at
           ]}
      )
    end)

    length(rows)
  end

  defp upsert_processes(rows, now, replace_fields) do
    process_rows =
      rows
      |> deduplicate(& &1.process.process_number)
      |> Enum.map(fn row -> Map.merge(row.process, %{inserted_at: now, updated_at: now}) end)

    process_rows
    |> Enum.chunk_every(2_000)
    |> Enum.each(fn chunk ->
      Repo.insert_all(MiningProcess, chunk,
        conflict_target: [:process_number],
        on_conflict: {:replace, replace_fields}
      )
    end)

    numbers = Enum.map(process_rows, & &1.process_number)

    MiningProcess
    |> where([process], process.process_number in ^numbers)
    |> select([process], {process.process_number, process.id})
    |> Repo.all()
    |> Map.new()
  end

  defp insert_changes(rows, existing, audit, now, field) do
    changes =
      rows
      |> Enum.filter(fn row ->
        old = Map.get(row, :old_fingerprint, Map.get(existing, row.mining_process_id))
        old != row.material_fingerprint
      end)
      |> Enum.map(fn row ->
        old = Map.get(row, :old_fingerprint, Map.get(existing, row.mining_process_id))

        %{
          mining_process_id: row.mining_process_id,
          source_import_id: audit.id,
          field: field,
          old_value: value_map(old),
          new_value: value_map(row.material_fingerprint),
          observed_at: now,
          fingerprint:
            Fingerprint.of(%{
              process: row.mining_process_id,
              field: field,
              old: old,
              new: row.material_fingerprint,
              source_checksum: audit.checksum_sha256
            }),
          inserted_at: now
        }
      end)

    changes
    |> Enum.chunk_every(2_000)
    |> Enum.each(&Repo.insert_all(ProcessChange, &1, on_conflict: :nothing))
  end

  defp remove_missing_availability(current_ids, existing, audit, now) do
    removed =
      AreaAvailability
      |> where([availability], availability.mining_process_id not in ^current_ids)
      |> select([availability], %{
        id: availability.id,
        mining_process_id: availability.mining_process_id,
        material_fingerprint: availability.material_fingerprint
      })
      |> Repo.all()

    insert_changes(
      Enum.map(removed, fn item ->
        %{
          mining_process_id: item.mining_process_id,
          material_fingerprint: nil,
          old_fingerprint: item.material_fingerprint
        }
      end),
      existing,
      audit,
      now,
      "availability_removed"
    )

    if removed != [] do
      ids = Enum.map(removed, & &1.id)
      AreaAvailability |> where([availability], availability.id in ^ids) |> Repo.delete_all()
    end
  end

  defp start_audit(source, source_url, started_at, observed_at, checksum, byte_size) do
    %SourceImport{}
    |> SourceImport.changeset(%{
      source: source,
      source_url: source_url,
      status: "running",
      started_at: started_at,
      source_modified_at: observed_at,
      checksum_sha256: checksum,
      byte_size: byte_size
    })
    |> Repo.insert()
  end

  defp previous_checksum?(source, checksum, current_id) do
    SourceImport
    |> where(
      [audit],
      audit.source == ^source and audit.id != ^current_id and audit.status == "succeeded"
    )
    |> order_by([audit], desc: audit.finished_at)
    |> limit(1)
    |> select([audit], audit.checksum_sha256)
    |> Repo.one() == checksum
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
      case reason do
        exception when is_exception(exception) -> Exception.message(exception)
        other -> inspect(other, limit: 20, printable_limit: 500)
      end
      |> String.slice(0, 240)

    case finish_audit(audit, %{
           status: "failed",
           finished_at: DateTime.utc_now(:second),
           error_summary: summary
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

  defp summarize_warnings(warnings) do
    warnings
    |> Enum.group_by(& &1.kind)
    |> Map.new(fn {kind, items} ->
      {kind, %{"count" => length(items), "samples" => Enum.take(items, 20)}}
    end)
  end

  defp value_map(nil), do: nil
  defp value_map(value), do: %{"fingerprint" => value}

  defp deduplicate(rows, key_fun), do: rows |> Map.new(&{key_fun.(&1), &1}) |> Map.values()

  defp sha256(path) do
    path
    |> File.stream!(64 * 1024, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end
end
