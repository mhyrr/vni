defmodule Mix.Tasks.Vni.Ingest.StateHistory do
  @shortdoc "Ingest statewide seats–votes history (MEDSL, 1976–2024)"

  @moduledoc """
  Upserts one row per state per cycle: House delegation split from MEDSL
  House winners, R share of the two-party presidential vote from MEDSL
  President in presidential years. Rerunnable — rows key on
  (state, cycle). Rules and caveats in `VNI.Politics.StateHistory`.

      mix vni.ingest.state_history
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_args) do
    alias VNI.Politics.StateHistory

    Mix.shell().info("Ingesting seats–votes history from #{StateHistory.house_source_url()} ...")
    summary = StateHistory.ingest!()

    Mix.shell().info("Done. #{summary.rows} state-cycle rows across #{summary.cycles} cycles.")

    for {cycle, total} <- Enum.sort(summary.off_total_cycles) do
      Mix.shell().error("Cycle #{cycle} sums to #{total} seats (expected 435) — inspect.")
    end
  end
end
