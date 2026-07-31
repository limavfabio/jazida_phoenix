defmodule JazidaPhoenix.Mining.Sync do
  @moduledoc "Downloads official artifacts and delegates to the audited import services."

  alias JazidaPhoenix.Mining.{Downloader, ImportAudit, Sigmine, Sople}

  def sople do
    config = Application.fetch_env!(:jazida_phoenix, :mining)

    result =
      with_downloads(
        {config[:sople_stock_url], "stock.csv"},
        {config[:sople_round_results_url], "rounds.csv"},
        fn stock, rounds ->
          with {:ok, stock_audit} <-
                 Sople.import_stock(stock.path,
                   source_url: config[:sople_stock_url],
                   observed_at: stock.source_modified_at || DateTime.utc_now()
                 ),
               {:ok, rounds_audit} <-
                 Sople.import_round_results(rounds.path,
                   source_url: config[:sople_round_results_url],
                   observed_at: rounds.source_modified_at || DateTime.utc_now()
                 ) do
            {:ok, %{stock: stock_audit, rounds: rounds_audit}}
          end
        end
      )

    case result do
      {:error, {:download_failed, :first, reason}} ->
        ImportAudit.record_download_failure("sople_stock", config[:sople_stock_url], reason)

      {:error, {:download_failed, :second, reason}} ->
        ImportAudit.record_download_failure(
          "sople_round_results",
          config[:sople_round_results_url],
          reason
        )

      other ->
        other
    end
  end

  def sigmine do
    config = Application.fetch_env!(:jazida_phoenix, :mining)

    source_url = "#{config[:sigmine_active_url]} + #{config[:sigmine_inactive_url]}"

    result =
      with_downloads(
        {config[:sigmine_active_url], "active.zip"},
        {config[:sigmine_inactive_url], "inactive.zip"},
        fn active, inactive ->
          Sigmine.import_archives(active.path, inactive.path,
            source_url: source_url,
            observed_at: latest_modified_at(active, inactive)
          )
        end
      )

    case result do
      {:error, {:download_failed, _position, reason}} ->
        ImportAudit.record_download_failure("sigmine", source_url, reason)

      other ->
        other
    end
  end

  defp with_downloads({first_url, first_name}, {second_url, second_name}, fun) do
    case Downloader.download(first_url, filename: first_name) do
      {:ok, first} ->
        try do
          case Downloader.download(second_url, filename: second_name) do
            {:ok, second} ->
              try do
                fun.(first, second)
              after
                Downloader.cleanup(second.directory)
              end

            {:error, reason} ->
              {:error, {:download_failed, :second, reason}}
          end
        after
          Downloader.cleanup(first.directory)
        end

      {:error, reason} ->
        {:error, {:download_failed, :first, reason}}
    end
  end

  defp latest_modified_at(first, second) do
    [first.source_modified_at, second.source_modified_at]
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> DateTime.utc_now() end)
  end
end
