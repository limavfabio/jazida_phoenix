defmodule JazidaPhoenix.Mining.ImportAudit do
  @moduledoc "Records failures that occur before a source artifact can enter an importer."

  require Logger

  alias JazidaPhoenix.Mining.SourceImport
  alias JazidaPhoenix.Repo

  def record_download_failure(source, source_url, reason) do
    now = DateTime.utc_now(:second)

    summary =
      if is_exception(reason),
        do: Exception.message(reason),
        else: inspect(reason, printable_limit: 500)

    result =
      %SourceImport{}
      |> SourceImport.changeset(%{
        source: source,
        source_url: source_url,
        status: "failed",
        started_at: now,
        finished_at: now,
        error_summary: String.slice(summary, 0, 240)
      })
      |> Repo.insert()

    case result do
      {:ok, audit} ->
        Logger.info("source import finished",
          source: audit.source,
          source_import_id: audit.id,
          outcome: audit.status,
          duration_ms: 0,
          parsed_rows: 0,
          imported_rows: 0,
          warning_count: 0
        )

        {:error, audit}

      error ->
        error
    end
  end
end
