defmodule JazidaPhoenix.Mining do
  @moduledoc "Public queries for the ANM opportunity catalog."

  import Ecto.Query

  alias JazidaPhoenix.Mining.{MiningProcess, SourceImport}
  alias JazidaPhoenix.Repo

  @max_results 100

  def list_processes(filters \\ %{}) do
    MiningProcess
    |> join(:left, [process], availability in assoc(process, :availability), as: :availability)
    |> apply_search(filters)
    |> apply_filter(:state_code, filters)
    |> apply_category(filters)
    |> apply_text_array_filter(:municipalities, filters, "municipality")
    |> apply_text_array_filter(:substances, filters, "substance")
    |> apply_raw_status(filters)
    |> apply_regime(filters)
    |> apply_round(filters)
    |> order_by([process], asc: process.process_number)
    |> limit(^limit(filters))
    |> preload([:availability])
    |> Repo.all()
  end

  def get_process(id) when is_integer(id), do: get_process(to_string(id))

  def get_process(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} ->
        Repo.get(MiningProcess, id) |> Repo.preload([:availability, round_areas: :round])

      _ ->
        nil
    end
  end

  def get_process_by_number(process_number) when is_binary(process_number) do
    Repo.get_by(MiningProcess, process_number: process_number)
    |> Repo.preload([:availability, round_areas: :round])
  end

  def latest_successful_import(source) do
    SourceImport
    |> where([import], import.source == ^source and import.status in ["succeeded", "unchanged"])
    |> order_by([import], desc: import.finished_at)
    |> limit(1)
    |> Repo.one()
  end

  def latest_import(source) do
    SourceImport
    |> where([import], import.source == ^source)
    |> order_by([import], desc: import.started_at, desc: import.id)
    |> limit(1)
    |> Repo.one()
  end

  def stale?(source, now \\ DateTime.utc_now()) do
    threshold = Application.fetch_env!(:jazida_phoenix, :mining)[:stale_after_hours]

    case latest_successful_import(source) do
      %{finished_at: finished_at} -> DateTime.diff(now, finished_at, :hour) > threshold
      nil -> true
    end
  end

  defp apply_search(query, filters) do
    case clean(filters, "q") do
      nil ->
        query

      term ->
        like = "%#{escape_like(term)}%"

        where(
          query,
          [process],
          ilike(process.process_number, ^like) or
            fragment("?::text ILIKE ? ESCAPE '!'", process.municipalities, ^like) or
            fragment("?::text ILIKE ? ESCAPE '!'", process.substances, ^like)
        )
    end
  end

  defp apply_filter(query, :state_code, filters) do
    case clean(filters, "state") do
      nil ->
        query

      state when byte_size(state) == 2 ->
        where(query, [process], process.state_code == ^String.upcase(state))

      _ ->
        query
    end
  end

  defp apply_category(query, filters) do
    case clean(filters, "category") do
      nil ->
        query

      category ->
        where(query, [availability: availability], availability.display_category == ^category)
    end
  end

  defp apply_text_array_filter(query, field, filters, key) do
    case clean(filters, key) do
      nil ->
        query

      term ->
        like = "%#{escape_like(term)}%"

        where(
          query,
          [process],
          fragment("array_to_string(?, ',') ILIKE ? ESCAPE '!'", field(process, ^field), ^like)
        )
    end
  end

  defp apply_raw_status(query, filters) do
    case clean(filters, "status") do
      nil ->
        query

      term ->
        like = "%#{escape_like(term)}%"

        where(
          query,
          [availability: availability],
          ilike(availability.stock_status_raw, ^like) or
            ilike(availability.latest_edital_status_raw, ^like)
        )
    end
  end

  defp apply_regime(query, filters) do
    case clean(filters, "regime") do
      nil ->
        query

      term ->
        like = "%#{escape_like(term)}%"

        where(
          query,
          [process, availability: availability],
          ilike(availability.availability_regime, ^like) or
            fragment(
              "EXISTS (SELECT 1 FROM round_areas ra WHERE ra.mining_process_id = ? AND ra.availability_regime ILIKE ? ESCAPE '!')",
              process.id,
              ^like
            )
        )
    end
  end

  defp apply_round(query, filters) do
    case parse_positive_integer(Map.get(filters, "round") || Map.get(filters, :round)) do
      nil ->
        query

      round_number ->
        where(
          query,
          [process],
          fragment(
            "EXISTS (SELECT 1 FROM round_areas ra JOIN rounds r ON r.id = ra.round_id WHERE ra.mining_process_id = ? AND r.number = ?)",
            process.id,
            ^round_number
          )
        )
    end
  end

  defp clean(filters, key) do
    atom_key =
      Map.fetch!(
        %{
          "q" => :q,
          "state" => :state,
          "category" => :category,
          "municipality" => :municipality,
          "substance" => :substance,
          "status" => :status,
          "regime" => :regime
        },
        key
      )

    case Map.get(filters, key) || Map.get(filters, atom_key) do
      value when is_binary(value) ->
        value = value |> String.trim() |> String.slice(0, 100)
        if value == "", do: nil, else: value

      _ ->
        nil
    end
  end

  defp limit(filters) do
    case Map.get(filters, "limit") do
      value when is_integer(value) -> value
      value when is_binary(value) -> elem(Integer.parse(value), 0)
      _ -> 50
    end
    |> min(@max_results)
    |> max(1)
  rescue
    _ -> 50
  end

  defp escape_like(value), do: String.replace(value, ["!", "%", "_"], fn char -> "!#{char}" end)

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: value

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> number
      _ -> nil
    end
  end

  defp parse_positive_integer(_value), do: nil
end
