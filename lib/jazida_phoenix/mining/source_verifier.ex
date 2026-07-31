defmodule JazidaPhoenix.Mining.SourceVerifier do
  @moduledoc "Checks local ANM source contracts without accessing or mutating the database."

  alias JazidaPhoenix.Mining.{AnmCSV, Archive, Status}

  @stock_headers ~w(
    ProcessoMinerario UnidadeFederacao Municipio AreaPoligonal Substancia UsoSubstancia
    RegimeDisponibilidade IndicaNominacao FaseProcessoMinerario SituacaoProcesso
    SituacaoEstoque IndicaDisponibilizacaoEdital UltimaSituacaoEdital
  )
  @round_headers ~w(
    Rodada NumeroArea ProcessoMinerario Situacao Modalidade RegimeDisponibilidade Municipio
    UnidadeFederacao AreaPoligonal ValorLanceVencedorReais NomeVencedor CpfCnpjVencedor
  )
  @sigmine_fields ~w(PROCESSO DSProcesso)

  def verify(paths) when is_map(paths) do
    checks = [
      {:stock, fn -> verify_csv(paths.stock, @stock_headers, [:stock, :result]) end},
      {:rounds, fn -> verify_csv(paths.rounds, @round_headers, [:round_result]) end},
      {:active, fn -> verify_sigmine(paths.active) end},
      {:inactive, fn -> verify_sigmine(paths.inactive) end}
    ]

    results = Map.new(checks, fn {name, check} -> {name, check.()} end)

    errors =
      for {name, {:error, reason}} <- results, into: %{} do
        {name, reason}
      end

    if errors == %{} do
      {:ok, Map.new(results, fn {name, {:ok, report}} -> {name, report} end)}
    else
      {:error, errors}
    end
  end

  defp verify_csv(path, expected_headers, vocabularies) do
    with :ok <- regular_file(path),
         [first | _] <- Enum.take(AnmCSV.rows(path), 1),
         :ok <- exact_headers(Map.keys(first), expected_headers),
         {:ok, statuses} <- status_vocabulary(path, vocabularies) do
      {:ok, %{headers: expected_headers, statuses: statuses}}
    else
      [] -> {:error, :empty_csv}
      {:error, _reason} = error -> error
    end
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  defp status_vocabulary(path, vocabularies) do
    values =
      Enum.reduce(AnmCSV.rows(path), %{}, fn row, acc ->
        Enum.reduce(vocabularies, acc, fn vocabulary, inner ->
          value = row[status_field(vocabulary)] |> blank_to_nil()
          Map.update(inner, vocabulary, MapSet.new([value]), &MapSet.put(&1, value))
        end)
      end)

    unknown =
      for {vocabulary, raw_values} <- values,
          raw <- raw_values,
          unknown_status?(vocabulary, raw),
          do: {vocabulary, raw}

    if unknown == [] do
      report =
        Map.new(values, fn {vocabulary, raw_values} ->
          {vocabulary, raw_values |> MapSet.delete(nil) |> Enum.sort()}
        end)

      {:ok, report}
    else
      {:error, {:unknown_statuses, unknown}}
    end
  end

  defp verify_sigmine(path) do
    with :ok <- regular_file(path),
         executable when is_binary(executable) <- System.find_executable("ogrinfo"),
         {:ok, shape_name} <- Archive.inspect_sigmine(path),
         virtual_path = "/vsizip/#{Path.expand(path)}/#{shape_name}",
         {output, 0} <-
           System.cmd(executable, ["-ro", "-so", "-al", virtual_path], stderr_to_stdout: true),
         :ok <- sigmine_contract(output) do
      {:ok, %{shape: shape_name, projection: "EPSG:4674", fields: @sigmine_fields}}
    else
      nil ->
        {:error, :ogrinfo_unavailable}

      {output, status} when is_integer(status) ->
        {:error, {:ogrinfo_failed, status, String.slice(output, 0, 500)}}

      {:error, _reason} = error ->
        error
    end
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  defp sigmine_contract(output) do
    missing_fields = Enum.reject(@sigmine_fields, &String.contains?(output, "#{&1}:"))

    cond do
      not String.contains?(output, ~s(ID["EPSG",4674])) -> {:error, :unexpected_projection}
      not String.contains?(output, "Geometry:") -> {:error, :missing_geometry_metadata}
      missing_fields != [] -> {:error, {:missing_fields, missing_fields}}
      true -> :ok
    end
  end

  defp exact_headers(actual, expected) do
    if MapSet.new(actual) == MapSet.new(expected),
      do: :ok,
      else: {:error, {:unexpected_headers, actual}}
  end

  defp regular_file(path) do
    case File.stat(path) do
      {:ok, %{type: :regular}} -> :ok
      {:ok, _stat} -> {:error, :not_a_regular_file}
      {:error, reason} -> {:error, {:file, reason}}
    end
  end

  defp status_field(:stock), do: "SituacaoEstoque"
  defp status_field(:result), do: "UltimaSituacaoEdital"
  defp status_field(:round_result), do: "Situacao"

  defp unknown_status?(:stock, raw), do: match?({:warning, _}, Status.stock(raw))
  defp unknown_status?(_vocabulary, raw), do: match?({:warning, _}, Status.result(raw))

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil
end
