defmodule Engine.SelectionRange do
  alias ElixirSense.Core.Normalized.Tokenizer
  alias Engine.SelectionRange.TokenRanges
  alias Forge.Ast
  alias Forge.Ast.Env
  alias Forge.Ast.Range
  alias Forge.Document
  alias Forge.Document.Lines
  alias GenLSP.Structures

  def selection_range(%Env{} = env) do
    tokens = Tokenizer.tokenize(Lines.to_string(env.document.lines)) |> Enum.reverse()

    TokenRanges.ranges(tokens)
    |> Enum.filter(&TokenRanges.contains?(&1, env.position))
    |> TokenRanges.sort_nested()

    # |> from_list()

    # tokens
    # IO.puts(:stderr, inspect(tokens, pretty: true, limit: 3000000))
    # with {:ok, ranges} <- from_ast(env.position, env.document) do
    #   # ranges
    #   tokens
    # else
    #   _ -> :error
    # end
  end

  defp from_list([]), do: nil

  defp from_list([{{start_line, start_column}, {end_line, end_column}} | tail]) do
    %Structures.SelectionRange{
      range: %Structures.Range{
        start: %Structures.Position{
          line: start_line,
          character: start_column
        },
        end: %Structures.Position{
          line: end_line,
          character: end_column
        }
      },
      parent: from_list(tail)
    }
  end

  defp from_ast(position, %Document{} = document) do
    with {:ok, path} <- Ast.path_at(document, position) do
      from_ast_path(path, document)
    end
  end

  defp from_ast_path([head | tail], %Document{} = document) do
    with {:ok, range} <- Range.fetch(head, document),
         {:ok, parent} <- from_ast_path(tail, document) do
      {:ok, %Structures.SelectionRange{range: range, parent: parent}}
    else
      _ -> :error
    end
  end

  defp from_ast_path([], %Document{} = _document), do: {:ok, nil}

  defmodule TokenRanges do
    def contains?({start_pos, end_pos}, pos) do
      pos = {pos.line, pos.character}
      start_pos <= pos and pos <= end_pos
    end

    def sort_nested(ranges) do
      Enum.sort(ranges, fn {a_start, _}, {b_start, _} ->
        a_start >= b_start
      end)
    end

    defmodule Frame do
      defstruct opening: nil, stops: []
    end

    @opening [:"(", :"[", :"{", :"<<", :do, :block_identifier, :with, :for, :case, :fn]
    @token_pairs %{
      "(": [:")"],
      "[": [:"]"],
      "{": [:"}"],
      "<<": [:">>"],
      # do blocks
      do: [:block_identifier, :end],
      block_identifier: [:block_identifier, :end],
      # other special forms that are not covered by :block_identifier
      with: [:do],
      for: [:do],
      case: [:do],
      fn: [:end]
    }
    @stop [:comma]

    def ranges(tokens) do
      {ranges, _stack} =
        Enum.reduce(tokens, {[], []}, fn token, acc ->
          handle_token(token, acc)
        end)

      Enum.reverse(ranges)
    end

    defp handle_token({kind, pos, _} = token, acc) do
      handle_token({kind, pos}, acc)
    end

    defp handle_token({kind, pos} = token, {ranges, stack}) do
      cond do
        opening_token?(kind) ->
          frame = %Frame{opening: token}
          {ranges, [frame | stack]}

        stop_token?(kind) ->
          handle_stop(pos, {ranges, stack})

        closing_token?(kind, stack) ->
          handle_close(kind, pos, {ranges, stack})

        true ->
          {ranges, stack}
      end
    end

    defp opening_token?(kind) do
      Map.has_key?(@token_pairs, kind)
    end

    defp stop_token?(kind) when kind in @stop, do: true
    defp stop_token?(_), do: false

    defp handle_stop(_pos, {ranges, []}), do: {ranges, []}

    defp handle_stop(pos, {ranges, [frame | rest]}) do
      from =
        case frame.stops do
          [] -> elem(frame.opening, 1)
          stops -> List.last(stops)
        end

      range = {from, pos}

      updated_frame =
        %Frame{frame | stops: frame.stops ++ [pos]}

      {[range | ranges], [updated_frame | rest]}
    end

    # ---- closing ----

    defp closing_token?(_kind, []), do: false

    defp closing_token?(kind, [frame | _]) do
      opening_kind = elem(frame.opening, 0)
      closing_kinds = Map.get(@token_pairs, opening_kind, [])
      kind in closing_kinds
    end

    defp handle_close(_kind, _pos, {ranges, []}),
      do: {ranges, []}

    defp handle_close(kind, pos, {ranges, [frame | rest]}) do
      opening_kind = elem(frame.opening, 0)
      closing_kinds = Map.get(@token_pairs, opening_kind, [])

      if kind in closing_kinds do
        from =
          case frame.stops do
            [] -> elem(frame.opening, 1)
            stops -> List.last(stops)
          end

        range = {from, pos}

        {[range | ranges], rest}
      else
        {ranges, [frame | rest]}
      end
    end
  end
end

# tokens = Tokenizer.tokenize(Lines.to_string(env.document.lines))
# IO.puts(:stderr, inspect(tokens, pretty: true, limit: 3000000))

# last = Lines.size(env.document.lines) - 1
# {:ok, line} = Document.fetch_text_at(env.document, last)

# position = Position.new(document, last, String.length(line))
# stream = Tokens.prefix_stream(env.document, position)

# tokens = Enum.into(stream, [])

# comment = with {:ok, comment} <- Map.fetch(analysis.comments_by_line, position.line),
#                 true <- position.character > comment[:column] do
#   comment
# end
