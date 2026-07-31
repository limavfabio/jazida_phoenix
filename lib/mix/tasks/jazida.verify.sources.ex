defmodule Mix.Tasks.Jazida.Verify.Sources do
  use Mix.Task

  @shortdoc "Verifies local SOPLE and SIGMINE source contracts without database writes"

  @switches [stock: :string, rounds: :string, active: :string, inactive: :string]

  @impl Mix.Task
  def run(args) do
    {options, positional, invalid} = OptionParser.parse(args, strict: @switches)

    if positional != [] or invalid != [] do
      Mix.raise(usage())
    end

    paths = Map.new(@switches, fn {name, _type} -> {name, Keyword.get(options, name)} end)

    if Enum.any?(paths, fn {_name, path} -> is_nil(path) end) do
      Mix.raise(usage())
    end

    case JazidaPhoenix.Mining.SourceVerifier.verify(paths) do
      {:ok, report} ->
        Mix.shell().info("ANM source contracts verified:\n#{inspect(report, pretty: true)}")

      {:error, errors} ->
        Mix.raise("ANM source verification failed: #{inspect(errors)}")
    end
  end

  defp usage do
    "usage: mix jazida.verify.sources --stock PATH --rounds PATH --active PATH --inactive PATH"
  end
end
