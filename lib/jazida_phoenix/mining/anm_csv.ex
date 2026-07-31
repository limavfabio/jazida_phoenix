defmodule JazidaPhoenix.Mining.AnmCSV do
  @moduledoc false

  NimbleCSV.define(Parser, separator: ";", escape: "\"")

  def rows(path) do
    path
    |> File.stream!([:trim_bom])
    |> Parser.parse_stream(skip_headers: false)
    |> Stream.transform(nil, fn
      header, nil -> {[], Enum.map(header, &clean_header/1)}
      values, header -> {[header |> Enum.zip(values) |> Map.new()], header}
    end)
  end

  def decimal(nil), do: nil
  def decimal(""), do: nil

  def decimal(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.replace(".", "")
    |> String.replace(",", ".")
    |> Decimal.parse()
    |> case do
      {decimal, ""} -> decimal
      _ -> nil
    end
  end

  def boolean(value) when is_binary(value),
    do: String.downcase(String.trim(value)) in ["sim", "true", "1"]

  def boolean(_value), do: false

  def values(value) when is_binary(value) do
    value
    |> String.split(";", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  def values(_value), do: []

  def state_code(value) when is_binary(value), do: Map.get(states(), String.trim(value))
  def state_code(_value), do: nil

  defp clean_header(header), do: header |> String.trim_leading(<<239, 187, 191>>) |> String.trim()

  defp states do
    %{
      "Acre" => "AC",
      "Alagoas" => "AL",
      "Amapá" => "AP",
      "Amazonas" => "AM",
      "Bahia" => "BA",
      "Ceará" => "CE",
      "Distrito Federal" => "DF",
      "Espírito Santo" => "ES",
      "Goiás" => "GO",
      "Maranhão" => "MA",
      "Mato Grosso" => "MT",
      "Mato Grosso do Sul" => "MS",
      "Minas Gerais" => "MG",
      "Pará" => "PA",
      "Paraíba" => "PB",
      "Paraná" => "PR",
      "Pernambuco" => "PE",
      "Piauí" => "PI",
      "Rio de Janeiro" => "RJ",
      "Rio Grande do Norte" => "RN",
      "Rio Grande do Sul" => "RS",
      "Rondônia" => "RO",
      "Roraima" => "RR",
      "Santa Catarina" => "SC",
      "São Paulo" => "SP",
      "Sergipe" => "SE",
      "Tocantins" => "TO"
    }
  end
end
