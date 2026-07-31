defmodule JazidaPhoenix.Mining.Downloader do
  @moduledoc "Bounded, streamed downloader for official source artifacts."

  def download(url, opts \\ []) when is_binary(url) do
    config = Application.fetch_env!(:jazida_phoenix, :mining)
    max_bytes = Keyword.get(opts, :max_bytes, config[:max_download_bytes])
    timeout = Keyword.get(opts, :timeout, config[:download_timeout_ms])
    request_options = Keyword.get(opts, :request_options, [])
    directory = Keyword.get_lazy(opts, :directory, &temporary_directory!/0)
    path = Path.join(directory, Keyword.get(opts, :filename, "source"))
    counter = :atomics.new(2, signed: false)

    result =
      File.open(path, [:write, :binary], fn file ->
        options =
          [
            receive_timeout: timeout,
            connect_options: [timeout: min(timeout, 30_000)],
            max_redirects: 5,
            retry: :transient,
            max_retries: 2,
            raw: true,
            into: fn {:data, data}, {request, response} ->
              size = :atomics.add_get(counter, 1, byte_size(data))

              if size <= max_bytes do
                :ok = IO.binwrite(file, data)
                {:cont, {request, response}}
              else
                :atomics.put(counter, 2, 1)
                {:halt, {request, response}}
              end
            end
          ]
          |> Keyword.merge(request_options)

        Req.get(url, options)
      end)

    with {:ok, {:ok, %Req.Response{status: status} = response}} when status in 200..299 <-
           result,
         0 <- :atomics.get(counter, 2),
         {:ok, stat} <- File.stat(path),
         true <- stat.size > 0 do
      {:ok,
       %{
         path: path,
         directory: directory,
         byte_size: stat.size,
         checksum_sha256: sha256(path),
         source_modified_at: source_modified_at(response)
       }}
    else
      1 ->
        cleanup(directory, {:error, :download_too_large})

      false ->
        cleanup(directory, {:error, :empty_download})

      {:ok, {:ok, %Req.Response{status: status}}} ->
        cleanup(directory, {:error, {:http_status, status}})

      {:ok, {:error, reason}} ->
        cleanup(directory, {:error, reason})

      {:error, reason} ->
        cleanup(directory, {:error, reason})
    end
  end

  def cleanup(directory) when is_binary(directory) do
    File.rm_rf(directory)
    :ok
  end

  defp cleanup(directory, result) do
    cleanup(directory)
    result
  end

  defp temporary_directory! do
    directory =
      Path.join(System.tmp_dir!(), "jazida-#{System.unique_integer([:positive, :monotonic])}")

    File.mkdir_p!(directory)
    directory
  end

  defp sha256(path) do
    path
    |> File.stream!(64 * 1024, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp source_modified_at(response) do
    case Req.Response.get_header(response, "last-modified") do
      [value | _] ->
        case Req.Utils.parse_http_date(value) do
          {:ok, datetime} -> datetime
          {:error, _reason} -> nil
        end

      [] ->
        nil
    end
  end
end
