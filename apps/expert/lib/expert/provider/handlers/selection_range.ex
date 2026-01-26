defmodule Expert.Provider.Handlers.SelectionRange do
  @behaviour Expert.Provider.Handler

  alias Expert.EngineApi

  alias Forge.Ast
  alias Forge.Ast.Range
  alias Forge.Ast.Tokens
  alias Forge.Document
  alias Forge.Document.Lines
  alias Forge.Document.Position
  alias Forge.Ast.Env
  alias Forge.Project
  alias Expert.ActiveProjects
  alias Expert.EngineApi
  alias GenLSP.Requests
  alias GenLSP.Structures
  alias ElixirSense.Core.Normalized.Tokenizer

  @impl Expert.Provider.Handler
  def handle(%Requests.TextDocumentSelectionRange{
        params: %Structures.SelectionRangeParams{} = params
      }) do
    project = Project.project_for_uri(ActiveProjects.projects(), params.text_document.uri)


      with {:ok, document, %Ast.Analysis{} = analysis} <-
             Document.Store.fetch(params.text_document.uri, :analysis) do
        ranges = for position <- params.positions do
          with {:ok, env} <- Env.new(project, analysis, position) do
            EngineApi.selection_range(project, env)
          end
        end
          IO.puts(:stderr, inspect(ranges, pretty: true, limit: 3_000_000))
          {:ok, ranges}
      end
  end
end
