defmodule VNIWeb.StateLive.Index do
  use VNIWeb, :live_view

  alias VNI.Politics
  alias VNI.Scores
  alias VNI.Scores.StateBias
  alias VNIWeb.StatePresenter

  @sorts ~w(skew gap seats authority state)

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "States",
       methodology_version: Scores.methodology_version(),
       mean_median_seat_floor: StateBias.mean_median_seat_floor()
     )}
  end

  def handle_params(params, _uri, socket) do
    sort = resolve_sort(params["sort"])
    cycles = Politics.latest_state_cycles()

    rows =
      StateBias.state_rows()
      |> Enum.map(&StatePresenter.present_index_row(&1, cycles[&1.state]))
      |> sort_rows(sort)

    {districted, at_large} = Enum.split_with(rows, &(!&1.at_large))

    {:noreply, assign(socket, sort: sort, districted_rows: districted, at_large_rows: at_large)}
  end

  defp resolve_sort(sort) when sort in @sorts, do: sort
  defp resolve_sort(_other), do: "gap"

  defp sort_rows(rows, "skew"), do: Enum.sort_by(rows, &(&1.skew_abs || -1), :desc)
  defp sort_rows(rows, "gap"), do: Enum.sort_by(rows, &gap/1, :desc)
  defp sort_rows(rows, "seats"), do: Enum.sort_by(rows, & &1.seats, :desc)
  defp sort_rows(rows, "state"), do: Enum.sort_by(rows, & &1.state)

  defp sort_rows(rows, "authority") do
    Enum.sort_by(rows, &{authority_rank(&1.authority), -(&1.skew_abs || -1)})
  end

  # Gap in seats, not points — a two-seat state's arithmetic noise must
  # not outrank a fifty-seat state's pattern.
  defp gap(row), do: if(row.gap_seats, do: abs(row.gap_seats), else: -1)

  # Commissions, courts, and special masters group first; the legislature
  # group sorts last, |skew| descending within each.
  defp authority_rank(:legislature), do: 1
  defp authority_rank(_authority), do: 0
end
