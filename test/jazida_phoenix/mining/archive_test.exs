defmodule JazidaPhoenix.Mining.ArchiveTest do
  use ExUnit.Case, async: true

  alias JazidaPhoenix.Mining.Archive

  test "rejects path traversal before extraction" do
    archive = temporary_path("unsafe.zip")
    {:ok, _} = :zip.create(String.to_charlist(archive), [{~c"../evil.shp", "evil"}], [])
    destination = temporary_path("extract")

    assert {:error, :unsafe_archive_path} = Archive.extract_sigmine(archive, destination)
    refute File.exists?(Path.join(Path.dirname(destination), "evil.shp"))
  end

  test "requires one shapefile and all core sidecars" do
    archive = temporary_path("incomplete.zip")
    {:ok, _} = :zip.create(String.to_charlist(archive), [{~c"source.shp", "shape"}], [])

    assert {:error, :unexpected_archive_layout} =
             Archive.extract_sigmine(archive, temporary_path("extract"))
  end

  test "extracts a bounded conventional layout" do
    archive = temporary_path("valid.zip")

    entries =
      for extension <- ~w(.shp .shx .dbf .prj) do
        {String.to_charlist("source#{extension}"), extension}
      end

    {:ok, _} = :zip.create(String.to_charlist(archive), entries, [])
    destination = temporary_path("valid-extract")

    assert {:ok, shape} = Archive.extract_sigmine(archive, destination)
    assert shape == Path.join(destination, "source.shp")
    assert File.read!(shape) == ".shp"
  end

  defp temporary_path(name) do
    directory =
      Path.join(System.tmp_dir!(), "jazida-archive-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf(directory) end)
    Path.join(directory, name)
  end
end
