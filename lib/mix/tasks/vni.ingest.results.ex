defmodule Mix.Tasks.Vni.Ingest.Results do
  @shortdoc "Ingest election results by district (margins + partisan lean)"

  @moduledoc """
  Updates last-margin and partisan-lean fields on district profiles from
  public datasets. Rerunnable — upserts key on district identity.

      mix vni.ingest.results

  Margins come from MEDSL "U.S. House 1976–2024" (cycles 2024 and 2022);
  lean is our own published formula (VNI.Politics.partisan_lean/2, never
  Cook PVI) over The Downballot's presidential-by-CD shares normalized
  against MEDSL national returns. Measurement rules and the local dataset
  caches are documented in `VNI.Politics.Results`.
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_args) do
    alias VNI.Politics.Results

    Mix.shell().info("Ingesting House margins from #{Results.house_source_url()} ...")
    margins = Results.ingest_margins!()

    Mix.shell().info(
      "Margins done. #{margins.ingested} districts updated" <>
        fallback_note(margins.fallback_cycles) <> "."
    )

    report_missing(margins.missing_districts)

    Mix.shell().info("Ingesting partisan lean from #{Results.lean_source_url()} ...")
    lean = Results.ingest_lean!()
    Mix.shell().info("Lean done. #{lean.ingested} districts updated.")
    report_missing(lean.missing_districts)
  end

  defp fallback_note(fallbacks) when fallbacks == %{}, do: ""

  defp fallback_note(fallbacks) do
    detail = Enum.map_join(fallbacks, ", ", fn {cycle, n} -> "#{n} from #{cycle}" end)
    " (#{detail} — latest general on record, cycle noted on the row)"
  end

  defp report_missing([]), do: :ok

  defp report_missing(missing) do
    Mix.shell().error("No current district for: #{Enum.join(missing, ", ")}")
  end
end
