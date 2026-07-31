defmodule JazidaPhoenix.Mining.ProcessNumber do
  @moduledoc "Strict normalization for ANM mining-process identifiers."

  @pattern ~r/\A(?<number>\d{1,6})\/(?<year>\d{4})\z/
  @sigmine_pattern ~r/\A\d{1,3}\.\d{3}\/\d{4}\z/

  def normalize(value) when is_binary(value) do
    value
    |> String.trim()
    |> parse()
  end

  def normalize(_value), do: :error

  def normalize_sigmine(value) when is_binary(value) do
    value = String.trim(value)

    if Regex.match?(@sigmine_pattern, value) do
      value |> String.replace(".", "") |> parse()
    else
      parse(value)
    end
  end

  def normalize_sigmine(_value), do: :error

  defp parse(value) do
    case Regex.named_captures(@pattern, value) do
      %{"number" => number, "year" => year} ->
        number = String.to_integer(number)
        year = String.to_integer(year)

        if number in 1..999_999 and year in 1900..2200 do
          {:ok,
           %{
             process_number: "#{String.pad_leading(to_string(number), 6, "0")}/#{year}",
             number: number,
             year: year
           }}
        else
          :error
        end

      nil ->
        :error
    end
  end
end
