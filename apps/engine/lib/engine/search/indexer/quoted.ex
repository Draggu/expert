defmodule Engine.Search.Indexer.Quoted do
  alias Engine.Search.Indexer.Source.Reducer
  alias Forge.Ast.Analysis
  alias Forge.Ast.Position
  alias Forge.Ast.Range
  alias Forge.ProcessCache
  alias Forge.Search.Indexer.Entry

  require ProcessCache

  def index_with_cleanup(%Analysis{} = analysis) do
    ProcessCache.with_cleanup do
      index(analysis)
    end
  end

  def index(analysis, extractors \\ nil)

  def index(
        %Analysis{valid?: true, expansions: expansions, document: document} = analysis,
        extractors
      ) do
    expansion_entries =
      Enum.flat_map(expansions, fn {range, ast} ->
        [_ | entries] = entreis_head = extract_entries(Analysis.new(ast, document), extractors)

        if !is_atom(ast) do
          File.write!(
            "/users/piotr/projects/my_project/expansion_ast.log",
            inspect(entreis_head, limit: :infinity, pretty: true) <> "\n----------------\n",
            [:append]
          )
        end

        {:ok, range} = Range.from_sourceror_range(range, document)

        Enum.map(entries, fn entry ->
          %{entry | range: range}
        end)
      end)

    regular_entries = extract_entries(analysis, extractors)

    File.write!(
      "/users/piotr/projects/my_project/regular.log",
      inspect(regular_entries, limit: :infinity, pretty: true) <> "\n----------------\n",
      [:append]
    )

    File.write!(
      "/users/piotr/projects/my_project/expansion.log",
      inspect(expansion_entries, limit: :infinity, pretty: true) <> "\n----------------\n",
      [:append]
    )

    {:ok, regular_entries ++ expansion_entries}
  end

  def index(%Analysis{valid?: false}, _extractors) do
    {:ok, []}
  end

  def extract_entries(%Analysis{} = analysis, extractors) do
    # TODO we should be able to stop visiting in depth once we found macro call
    {_, reducer} =
      Macro.prewalk(analysis.ast, Reducer.new(analysis, extractors), fn elem, reducer ->
        {reducer, elem} = Reducer.reduce(reducer, elem)
        {elem, reducer}
      end)

    Reducer.entries(reducer)
  end
end
