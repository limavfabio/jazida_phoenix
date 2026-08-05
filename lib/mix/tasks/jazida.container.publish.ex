defmodule Mix.Tasks.Jazida.Container.Publish do
  @moduledoc """
  Builds the production container with Podman and publishes it to GHCR.

      mix jazida.container.publish
      mix jazida.container.publish --image ghcr.io/owner/image --tag v1.0.0

  The default tag is the current 12-character Git revision. Both that tag and
  `latest` are pushed. Authenticate Podman with GHCR before running the task.
  """

  use Mix.Task

  @shortdoc "Builds the container locally and publishes it to GHCR"

  @default_image "ghcr.io/norte-brasil-digital/jazida_phoenix"
  @switches [image: :string, tag: :string]

  @impl Mix.Task
  def run(args) do
    {options, positional, invalid} = OptionParser.parse(args, strict: @switches)

    if positional != [] or invalid != [] do
      Mix.raise(usage())
    end

    image = Keyword.get(options, :image, @default_image)
    tag = Keyword.get_lazy(options, :tag, &git_revision!/0)
    versioned_image = "#{image}:#{tag}"
    latest_image = "#{image}:latest"

    run!("podman", ["build", "--tag", versioned_image, "."])
    run!("podman", ["tag", versioned_image, latest_image])
    run!("podman", ["push", versioned_image])
    run!("podman", ["push", latest_image])

    Mix.shell().info("Published #{versioned_image} and #{latest_image}")
  end

  defp git_revision! do
    case System.cmd("git", ["rev-parse", "--short=12", "HEAD"], stderr_to_stdout: true) do
      {revision, 0} -> String.trim(revision)
      {output, _status} -> Mix.raise("could not determine Git revision: #{String.trim(output)}")
    end
  end

  defp run!(executable, args) do
    case System.cmd(executable, args,
           into: IO.stream(:stdio, :line),
           stderr_to_stdout: true
         ) do
      {_output, 0} -> :ok
      {_output, status} -> Mix.raise("#{executable} exited with status #{status}")
    end
  end

  defp usage do
    "usage: mix jazida.container.publish [--image ghcr.io/OWNER/IMAGE] [--tag TAG]"
  end
end
