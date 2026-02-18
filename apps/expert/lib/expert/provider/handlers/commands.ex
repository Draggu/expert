defmodule Expert.Provider.Handlers.Commands do
  @behaviour Expert.Provider.Handler

  alias Expert.ActiveProjects
  alias Expert.EngineApi
  alias Forge.Open
  alias Forge.Project
  alias GenLSP.Enumerations.ErrorCodes
  alias GenLSP.Requests
  alias GenLSP.Structures

  require Logger

  @reindex_name "Reindex"
  @report_name "Report"

  def names do
    [@reindex_name, @report_name]
  end

  def reindex_command(%Project{} = project) do
    project_name = Project.name(project)

    %Structures.Command{
      title: "Rebuild #{project_name}'s code search index",
      command: @reindex_name
    }
  end

  @impl Expert.Provider.Handler
  def handle(%Requests.WorkspaceExecuteCommand{
        params: %Structures.ExecuteCommandParams{} = params
      }) do
    projects = ActiveProjects.projects()

    response =
      case params.command do
        @reindex_name ->
          project_names = Enum.map_join(projects, ", ", &Project.name/1)
          Logger.info("Reindex #{project_names}")
          reindex_all(projects)

        @report_name ->
          report(projects)

        invalid ->
          message = "#{invalid} is not a valid command"
          internal_error(message)
      end

    {:ok, response}
  end

  defp report(projects) do
    report_path = Path.join(File.cwd!(), ".expert/report")

    prepare_report_from_logs(report_path, projects)

    report_path
    |> issue_body()
    |> github_issue_link()
    |> Open.open_link()
  end

  defp github_issue_link(body) do
    query =
      URI.encode_query(%{
        body: body
      })

    %URI{
      scheme: "https",
      host: "github.com",
      path: "/elixir-lang/expert/issues/new",
      query: query
    }
    |> URI.to_string()
  end

  defp issue_body(report_path) do
    elixir_version = System.version()
    erlang_version = :version |> :erlang.system_info() |> to_string()

    """
    **Elixir Version:** #{elixir_version}
    **Erlang Version:** #{erlang_version}

    **Description of the Issue:**
    Please describe the issue you are experiencing in detail.

    **Steps to Reproduce:**
    1.
    2.
    3.

    **Expected Behavior:**
    <!--- Describe what you expected to happen. -->

    **Actual Behavior:**
    <!--- Describe what actually happened. -->

    **Additional Files / Logs:**
    Please attach any relevant files or logs here.
    <!--- Please attach `#{report_path}` -->
    """
  end

  defp prepare_report_from_logs(report_path, projects) do
    %{metadata: %{instance_id: instance_id}} = :logger.get_primary_config()

    with {:ok, log_file} <- File.open(report_path, [:write]) do
      Enum.each(projects, fn project ->
        project
        |> Project.log_file_path()
        |> log_lines(log_file, instance_id)
      end)

      File.cwd!()
      |> Path.join(".expert/expert.log")
      |> log_lines(log_file, instance_id)

      File.close(log_file)
    end
  end

  defp log_lines(path, output_device, instance_id) do
    with {:ok, input_device} <- File.open(path, [:read]) do
      try do
        input_device
        |> IO.stream(:line)
        |> Stream.filter(
          &Regex.match?(~r/^\d\d:\d\d:\d\d\.\d\d\d instance_id=#{instance_id} /Um, &1)
        )
        |> Enum.each(&IO.binwrite(output_device, &1))
      after
        File.close(input_device)
      end
    end
  end

  defp reindex_all(projects) do
    Enum.reduce_while(projects, :ok, fn project, _ ->
      case EngineApi.reindex(project) do
        :ok ->
          {:cont, "ok"}

        error ->
          GenLSP.notify(Expert.get_lsp(), %GenLSP.Notifications.WindowShowMessage{
            params: %GenLSP.Structures.ShowMessageParams{
              type: GenLSP.Enumerations.MessageType.error(),
              message: "Indexing #{Project.name(project)} failed"
            }
          })

          Logger.error("Indexing command failed due to #{inspect(error)}")

          {:halt, internal_error("Could not reindex: #{error}")}
      end
    end)
  end

  defp internal_error(message) do
    %GenLSP.ErrorResponse{code: ErrorCodes.internal_error(), message: message}
  end
end
