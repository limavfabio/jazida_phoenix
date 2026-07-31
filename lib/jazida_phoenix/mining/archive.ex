defmodule JazidaPhoenix.Mining.Archive do
  @moduledoc "Validates and extracts bounded SIGMINE archives without trusting entry paths."

  @required_extensions ~w(.shp .shx .dbf .prj)

  def inspect_sigmine(path) do
    config = Application.fetch_env!(:jazida_phoenix, :mining)

    with {:ok, entries} <- :zip.table(String.to_charlist(path)),
         files <- Enum.filter(entries, &match?({:zip_file, _, _, _, _, _}, &1)),
         :ok <- validate_count(files, config[:max_archive_entries]),
         :ok <- validate_paths(files),
         :ok <- validate_size(files, config[:max_archive_uncompressed_bytes]),
         {:ok, shape_name} <- validate_layout(files) do
      {:ok, shape_name}
    else
      {:error, _reason} = error -> error
      other -> {:error, {:invalid_archive, other}}
    end
  end

  def extract_sigmine(path, destination) do
    with {:ok, shape_name} <- inspect_sigmine(path),
         :ok <- File.mkdir_p(destination),
         {:ok, _files} <-
           :zip.extract(String.to_charlist(path), cwd: String.to_charlist(destination)) do
      {:ok, Path.join(destination, shape_name)}
    else
      {:error, _reason} = error -> error
      other -> {:error, {:invalid_archive, other}}
    end
  end

  defp validate_count(files, max) when length(files) <= max, do: :ok
  defp validate_count(_files, _max), do: {:error, :too_many_archive_entries}

  defp validate_paths(files) do
    if Enum.all?(files, fn {:zip_file, name, file_info, _, _, _} ->
         elem(file_info, 2) == :regular and safe_path?(List.to_string(name))
       end) do
      :ok
    else
      {:error, :unsafe_archive_path}
    end
  end

  defp safe_path?(name) do
    Path.type(name) == :relative and
      ".." not in Path.split(name) and
      not String.contains?(name, <<0>>)
  end

  defp validate_size(files, max) do
    size =
      Enum.reduce(files, 0, fn {:zip_file, _name, file_info, _, _, _}, total ->
        total + elem(file_info, 1)
      end)

    if size <= max, do: :ok, else: {:error, :archive_uncompressed_too_large}
  end

  defp validate_layout(files) do
    names = Enum.map(files, fn {:zip_file, name, _, _, _, _} -> List.to_string(name) end)
    shapes = Enum.filter(names, &(String.downcase(Path.extname(&1)) == ".shp"))

    with [shape] <- shapes,
         base = Path.rootname(shape),
         true <- Enum.all?(@required_extensions, &extension_present?(names, base, &1)) do
      {:ok, shape}
    else
      _ -> {:error, :unexpected_archive_layout}
    end
  end

  defp extension_present?(names, base, extension) do
    expected = String.downcase(base <> extension)
    Enum.any?(names, &(String.downcase(&1) == expected))
  end
end
