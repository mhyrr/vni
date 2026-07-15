defmodule VNIWeb.SourcesLive do
  @moduledoc """
  The public face of `docs/data-sources.md`, the ingest registry of record.

  The markdown is parsed at compile time (`@external_resource`), so the page
  can never drift from the registry: update the file in the same commit as
  the ingest and the page follows. No markdown dependency — the registry's
  shape is fixed (one pipe table, one `## Notes` section), so twenty lines
  of stdlib beat a renderer we'd restyle anyway.
  """

  use VNIWeb, :live_view

  @registry_path "docs/data-sources.md"
  @external_resource @registry_path

  {table_md, notes_md} =
    @registry_path
    |> File.read!()
    |> String.split("\n## Notes\n", parts: 2)
    |> List.to_tuple()

  @sources table_md
           |> String.split("\n")
           |> Enum.filter(&String.starts_with?(&1, "| ["))
           |> Enum.map(fn line ->
             [source, feeds, publisher, license] =
               line
               |> String.split("|", trim: true)
               |> Enum.map(&String.trim/1)

             [_, name, url] = Regex.run(~r/\[(.+?)\]\((.+?)\)/, source)

             %{name: name, url: url, feeds: feeds, publisher: publisher, license: license}
           end)

  @notes notes_md
         |> String.split("\n\n")
         |> Enum.map(&String.trim/1)
         |> Enum.reject(&(&1 == ""))
         |> Enum.map(fn paragraph ->
           [_, title, body] = Regex.run(~r/\A\*\*(.+?)\*\*\s*(.+)\z/s, paragraph)

           body =
             body
             |> String.replace(~r/\s+/, " ")
             |> String.replace("`", "")

           %{title: String.trim_trailing(title, "."), body: body}
         end)

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Data sources")
     |> assign(:sources, @sources)
     |> assign(:notes, @notes)}
  end
end
