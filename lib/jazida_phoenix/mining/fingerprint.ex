defmodule JazidaPhoenix.Mining.Fingerprint do
  @moduledoc false

  def of(value) do
    value
    |> normalize()
    |> Jason.encode_to_iodata!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp normalize(%Decimal{} = decimal), do: Decimal.to_string(decimal, :normal)
  defp normalize(%_{} = struct), do: struct |> Map.from_struct() |> normalize()

  defp normalize(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {key, normalize(value)} end)

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)

  defp normalize(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&normalize/1)

  defp normalize(value), do: value
end
