defmodule Engine.CodeIntelligence.Definition do
  alias Engine.CodeIntelligence.Entity
  alias Engine.Search.Store
  alias Forge.Document
  alias Forge.Document.Location
  alias Forge.Document.Position
  alias Forge.Formats
  alias Forge.Search.Indexer.Entry

  require Logger

  @spec definition(Document.t(), Position.t()) :: {:ok, [Location.t()]} | {:error, String.t()}
  def definition(%Document{} = document, %Position{} = position) do
    with {:ok, _, analysis} <- Document.Store.fetch(document.uri, :analysis),
         {:ok, entity, _range} <- Entity.resolve(analysis, position) do
      fetch_definition(entity)
    end
  end

  defp fetch_definition({type, entity} = resolved)
       when type in [:struct, :module] do
    module = Formats.module(entity)

    locations =
      case Store.exact(module, type: type, subtype: :definition) do
        {:ok, entries} ->
          for entry <- entries,
              result = to_location(entry),
              match?({:ok, _}, result) do
            {:ok, location} = result
            location
          end

        _ ->
          []
      end

    normalize_locations(resolved, locations)
  end

  defp fetch_definition({:call, module, function, arity} = resolved) do
    mfa = Formats.mfa(module, function, arity)

    definitions =
      mfa
      |> query_search_index(subtype: :definition)
      |> Stream.flat_map(fn entry ->
        case entry do
          %Entry{type: {:function, :delegate}} ->
            mfa = get_in(entry, [:metadata, :original_mfa])
            query_search_index(mfa, subtype: :definition) ++ [entry]

          _ ->
            [entry]
        end
      end)
      |> Stream.uniq_by(& &1.subject)

    locations =
      for entry <- definitions,
          result = to_location(entry),
          match?({:ok, _}, result) do
        {:ok, location} = result
        location
      end

    normalize_locations(resolved, locations)
  end

  defp fetch_definition(_) do
    {:error, :not_found}
  end

  defp normalize_locations(resolved, locations) do
    case locations do
      [] ->
        Logger.info("No definition found for #{inspect(resolved)} with Indexer.")

        {:error, :not_found}

      [location] ->
        {:ok, location}

      _ ->
        {:ok, locations}
    end
  end

  defp to_location(entry) do
    uri = Document.Path.ensure_uri(entry.path)

    case Document.Store.open_temporary(uri) do
      {:ok, document} ->
        {:ok, Location.new(entry.range, document)}

      _ ->
        :error
    end
  end

  defp query_search_index(subject, condition) do
    case Store.exact(subject, condition) do
      {:ok, entries} ->
        entries

      _ ->
        []
    end
  end
end
