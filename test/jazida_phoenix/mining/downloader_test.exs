defmodule JazidaPhoenix.Mining.DownloaderTest do
  use ExUnit.Case, async: true

  alias JazidaPhoenix.Mining.Downloader

  test "streams a successful response and computes its checksum" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("last-modified", "Mon, 29 Jul 2024 12:34:56 GMT")
      |> Plug.Conn.send_resp(200, "official-source")
    end)

    assert {:ok, download} =
             Downloader.download("https://anm.test/source",
               max_bytes: 100,
               request_options: [plug: {Req.Test, __MODULE__}]
             )

    assert File.read!(download.path) == "official-source"
    assert download.byte_size == 15
    assert download.source_modified_at == ~U[2024-07-29 12:34:56Z]

    assert download.checksum_sha256 ==
             Base.encode16(:crypto.hash(:sha256, "official-source"), case: :lower)

    Downloader.cleanup(download.directory)
  end

  test "rejects empty, oversized, and unsuccessful responses and cleans temporary files" do
    Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 200, "too-large") end)

    assert {:error, :download_too_large} =
             Downloader.download("https://anm.test/large",
               max_bytes: 3,
               request_options: [plug: {Req.Test, __MODULE__}, retry: false]
             )

    Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 503, "unavailable") end)

    assert {:error, {:http_status, 503}} =
             Downloader.download("https://anm.test/failure",
               request_options: [plug: {Req.Test, __MODULE__}, retry: false]
             )
  end
end
