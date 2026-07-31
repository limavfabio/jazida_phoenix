defmodule JazidaPhoenix.Mining.SopleParser do
  @moduledoc false

  alias JazidaPhoenix.Mining.{AnmCSV, Fingerprint, ProcessNumber, Status}

  def stock_rows(path), do: parse(path, &stock_row/1)
  def round_rows(path), do: parse(path, &round_row/1)

  defp parse(path, mapper) do
    path
    |> AnmCSV.rows()
    |> Enum.reduce(%{rows: [], warnings: []}, fn raw, acc ->
      case mapper.(raw) do
        {:ok, row} -> %{acc | rows: [row | acc.rows]}
        {:warning, warning} -> %{acc | warnings: [warning | acc.warnings]}
      end
    end)
    |> then(fn result ->
      %{result | rows: Enum.reverse(result.rows), warnings: Enum.reverse(result.warnings)}
    end)
  end

  defp stock_row(raw) do
    with {:ok, process} <- ProcessNumber.normalize(raw["ProcessoMinerario"]) do
      stock_raw = blank_to_nil(raw["SituacaoEstoque"])
      edital_raw = blank_to_nil(raw["UltimaSituacaoEdital"])
      area = AnmCSV.decimal(raw["AreaPoligonal"])
      {area, area_warnings} = valid_area(area, raw)
      {category, status_warnings} = category(Status.availability(stock_raw, edital_raw), raw)

      material = %{
        availability_regime: blank_to_nil(raw["RegimeDisponibilidade"]),
        stock_status_raw: stock_raw,
        latest_edital_status_raw: edital_raw,
        display_category: category,
        nominated: AnmCSV.boolean(raw["IndicaNominacao"]),
        listed_in_edital: AnmCSV.boolean(raw["IndicaDisponibilizacaoEdital"])
      }

      {:ok,
       %{
         process:
           Map.merge(process, %{
             state_code: AnmCSV.state_code(raw["UnidadeFederacao"]),
             municipalities: AnmCSV.values(raw["Municipio"]),
             area_ha: area,
             phase: blank_to_nil(raw["FaseProcessoMinerario"]),
             last_event: blank_to_nil(raw["SituacaoProcesso"]),
             substances: AnmCSV.values(raw["Substancia"]),
             substance_uses: AnmCSV.values(raw["UsoSubstancia"])
           }),
         availability: Map.put(material, :material_fingerprint, Fingerprint.of(material)),
         warnings: status_warnings ++ area_warnings
       }}
    else
      :error ->
        {:warning, %{kind: "invalid_process_number", value: sanitized(raw["ProcessoMinerario"])}}
    end
  end

  defp round_row(raw) do
    with {:ok, process} <- ProcessNumber.normalize(raw["ProcessoMinerario"]),
         {round_number, ""} <- Integer.parse(raw["Rodada"] || ""),
         {area_number, ""} <- Integer.parse(raw["NumeroArea"] || "") do
      situation = blank_to_nil(raw["Situacao"]) || "Sem situação informada"
      {category, warnings} = category(Status.result(situation), raw)

      material = %{
        round_number: round_number,
        area_number: area_number,
        modality: blank_to_nil(raw["Modalidade"]) || "Não informada",
        availability_regime: blank_to_nil(raw["RegimeDisponibilidade"]),
        situation_raw: situation,
        display_category: category,
        winning_bid_brl: AnmCSV.decimal(raw["ValorLanceVencedorReais"])
      }

      {:ok,
       %{
         process:
           Map.merge(process, %{
             state_code: AnmCSV.state_code(raw["UnidadeFederacao"]),
             municipalities: AnmCSV.values(raw["Municipio"]),
             area_ha: AnmCSV.decimal(raw["AreaPoligonal"])
           }),
         round_area: Map.put(material, :material_fingerprint, Fingerprint.of(material)),
         warnings: warnings
       }}
    else
      _ -> {:warning, %{kind: "invalid_round_row", process: sanitized(raw["ProcessoMinerario"])}}
    end
  end

  defp category({:ok, category}, _raw), do: {category || "unknown", []}

  defp category({:warning, category}, raw) do
    {category, [%{kind: "unknown_status", process: sanitized(raw["ProcessoMinerario"])}]}
  end

  defp blank_to_nil(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: String.trim(value))

  defp blank_to_nil(_value), do: nil

  defp sanitized(value) when is_binary(value), do: String.slice(value, 0, 80)
  defp sanitized(_value), do: nil

  defp valid_area(%Decimal{} = area, raw) do
    if Decimal.negative?(area) do
      {nil, [%{kind: "invalid_area", process: sanitized(raw["ProcessoMinerario"])}]}
    else
      {area, []}
    end
  end

  defp valid_area(area, _raw), do: {area, []}
end
