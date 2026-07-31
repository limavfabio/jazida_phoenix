defmodule JazidaPhoenix.Mining.Status do
  @moduledoc "Maps raw ANM labels to non-legal, navigational display categories."

  @stock %{
    "Para Análise" => "pending_analysis",
    "Em Análise" => "under_analysis",
    "Apta para Disponibilidade" => "eligible",
    "Não apta para Disponibilidade" => "not_eligible"
  }

  @result %{
    "Aguardando Leilão" => "awaiting_auction",
    "Livre" => "free",
    "Conquistada" => "awarded",
    "Arrematada" => "awarded",
    "Requerido" => "requested",
    "Não Requerida" => "unrequested",
    "Suspensa" => "suspended",
    "Retirada" => "withdrawn",
    "Edital Cancelado" => "cancelled"
  }

  def stock(raw), do: category(@stock, raw)
  def result(raw), do: category(@result, raw)

  def availability(stock_raw, latest_edital_raw) do
    case result(latest_edital_raw) do
      {:ok, nil} -> stock(stock_raw)
      result -> result
    end
  end

  def known_categories do
    @stock |> Map.values() |> Kernel.++(Map.values(@result)) |> Enum.uniq()
  end

  defp category(_mapping, raw) when raw in [nil, ""], do: {:ok, nil}

  defp category(mapping, raw) when is_binary(raw) do
    raw = String.trim(raw)

    case Map.fetch(mapping, raw) do
      {:ok, category} -> {:ok, category}
      :error -> {:warning, "unknown"}
    end
  end

  defp category(_mapping, _raw), do: {:warning, "unknown"}
end
