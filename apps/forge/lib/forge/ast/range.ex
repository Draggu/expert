defmodule Forge.Ast.Range do
  @moduledoc """
  Utilities for extracting ranges from ast nodes
  """
  alias Forge.Document
  alias Forge.Document.Position
  alias Forge.Document.Range

  @spec fetch(Macro.t(), Document.t()) :: {:ok, Range.t()} | :error
  def fetch(ast, %Document{} = document) do
    ast |> Sourceror.get_range() |> from_sourceror_range(document)
  end

  def from_sourceror_range(
        %Sourceror.Range{start: start_pos, end: end_pos},
        %Document{} = document
      ) do
    [line: start_line, column: start_column] = start_pos
    [line: end_line, column: end_column] = end_pos

    range =
      Range.new(
        Position.new(document, start_line, start_column),
        Position.new(document, end_line, end_column)
      )

    {:ok, range}
  end

  def from_sourceror_range(_, _), do: :error

  @spec fetch!(Macro.t(), Document.t()) :: Range.t()
  def fetch!(ast, %Document{} = document) do
    case fetch(ast, document) do
      {:ok, range} ->
        range

      :error ->
        raise ArgumentError,
          message: "Could not get a range for #{inspect(ast)} in #{document.path}"
    end
  end

  @spec get(Macro.t(), Document.t()) :: Range.t() | nil
  def get(ast, %Document{} = document) do
    case fetch(ast, document) do
      {:ok, range} -> range
      :error -> nil
    end
  end
end
