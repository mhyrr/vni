defmodule VNIWeb.StatePresenter do
  @moduledoc """
  Turns `VNI.Scores.StateBias` rows and `VNI.Politics.StateCycle` facts into
  the small, sourced maps consumed by the public `/states` LiveViews.

  Doctrine: every bias number is rendered with its authorship fact adjacent
  — the map's author is part of the number, never a footnote. No composite
  state score and no ordinal rank are ever produced here; sorting happens
  over the raw measures, not a synthesized verdict.
  """

  alias VNI.Politics.StateCycle
  alias VNIWeb.DistrictPresenter

  @doc "Full state name for a two-letter postal code."
  def state_name(code), do: DistrictPresenter.state_name(code)

  @doc """
  One `/states` index row: the state-bias row plus its latest seats–votes
  cycle, formatted for the table and carrying the raw numbers sort needs.
  """
  def present_index_row(row, cycle) do
    %{
      state: row.state,
      state_code: String.downcase(row.state),
      state_name: state_name(row.state),
      seats: row.seats,
      at_large: row.at_large,
      authority: row.authority,
      controlling_party: row.controlling_party,
      authority_label: authority_label(row.authority),
      party_badge_key: party_badge(row.authority, row.controlling_party),
      party_badge_label: party_badge_letter(row.controlling_party),
      pres_vote_display: vote_pair_display(cycle),
      seats_display: seats_pair_display(cycle),
      skew_display: skew_label(row.mean_median),
      skew_missing: is_nil(row.mean_median),
      skew_abs: row.mean_median && abs(row.mean_median),
      r_vote_pct: cycle && cycle.pres_r_share,
      r_seat_pct: r_seat_pct(cycle),
      worst_district_slug: row.worst_district_slug,
      worst_district_label: district_label(row.worst_district_slug)
    }
  end

  @doc """
  A `/states/:state` show-page presentation: authorship, the fact pair, the
  skew tier, and a ready-to-render history chart.
  """
  def present_show(row, cycle, history) do
    %{
      state: row.state,
      state_name: state_name(row.state),
      seats: row.seats,
      seats_label: seats_label(row.seats, row.at_large),
      at_large: row.at_large,
      authority: row.authority,
      authority_full: authority_full(row.authority, row.controlling_party),
      authorship_source_url: row.authorship_source_url,
      fact_pair: fact_pair(cycle),
      mean_median: row.mean_median,
      skew_display: skew_label(row.mean_median),
      worst_district_slug: row.worst_district_slug,
      worst_district_label: district_label(row.worst_district_slug),
      chart_svg: chart_svg(history)
    }
  end

  # -- Authority + party grammar -------------------------------------------

  def authority_label(:legislature), do: "State legislature"
  def authority_label(:independent_commission), do: "Independent commission"
  def authority_label(:politician_commission), do: "Politician commission"
  def authority_label(:court), do: "Court-drawn"
  def authority_label(:special_master), do: "Court-appointed special master"
  def authority_label(nil), do: nil

  # Party control at adoption only means something where a party could
  # hold the pen: legislatures and politician commissions. Independent
  # commissions and courts carry no party suffix, whatever the raw data.
  def controlling_party_suffix(authority, party)
      when authority in [:legislature, :politician_commission],
      do: party_suffix(party)

  def controlling_party_suffix(_authority, _party), do: nil

  defp party_suffix(:dem), do: "Democratic control at adoption"
  defp party_suffix(:rep), do: "Republican control at adoption"
  defp party_suffix(:split), do: "split control"
  defp party_suffix(:nonpartisan), do: nil
  defp party_suffix(nil), do: nil

  @doc "Combined authority sentence for the state show page hero."
  def authority_full(authority, party) do
    case {authority_label(authority), controlling_party_suffix(authority, party)} do
      {nil, _} -> nil
      {label, nil} -> label
      {label, suffix} -> "#{label} · #{suffix}"
    end
  end

  defp party_badge(authority, party)
       when authority in [:legislature, :politician_commission] and party in [:dem, :rep],
       do: party

  defp party_badge(_authority, _party), do: nil

  defp party_badge_letter(:dem), do: "D"
  defp party_badge_letter(:rep), do: "R"
  defp party_badge_letter(_party), do: nil

  defp seats_label(1, true), do: "1 seat, at-large"
  defp seats_label(seats, _at_large), do: "#{seats} seats"

  # -- Skew (mean–median gap) grammar --------------------------------------

  @doc """
  Formatted skew per state code — feeds the /districts map-skew sort,
  where every card carries its statewide gap. Nil below the seat floor.
  """
  def skew_by_state(level \\ :congressional) do
    Map.new(VNI.Scores.StateBias.state_rows(level), &{&1.state, skew_label(&1.mean_median)})
  end

  @doc "Skew string in lean grammar: R+2.9 / D+0.8 / EVEN, one decimal."
  def skew_label(nil), do: nil

  def skew_label(value) do
    rounded = Float.round(value / 1, 1)

    cond do
      rounded == 0.0 -> "EVEN"
      rounded > 0 -> "R+#{decimal1(rounded)}"
      true -> "D+#{decimal1(-rounded)}"
    end
  end

  # -- Fact pair (StateCycle) ------------------------------------------------

  def vote_pair_display(nil), do: "—"
  def vote_pair_display(%StateCycle{pres_r_share: nil}), do: "—"

  def vote_pair_display(%StateCycle{pres_r_share: r}),
    do: "#{decimal1(r)} / #{decimal1(100 - r)}"

  def seats_pair_display(nil), do: "—"

  def seats_pair_display(%StateCycle{seats_rep: r, seats_dem: d}), do: "#{r} / #{d}"

  def r_seat_pct(nil), do: nil

  def r_seat_pct(%StateCycle{} = cycle) do
    total = StateCycle.total_seats(cycle)
    if total > 0, do: 100 * cycle.seats_rep / total
  end

  @doc """
  The seats-and-votes fact pair for the state show page: two published
  facts side by side, never a synthesized statistic. Nil when the latest
  cycle has no presidential share (a midterm-only record).
  """
  def fact_pair(nil), do: nil
  def fact_pair(%StateCycle{pres_r_share: nil}), do: nil

  def fact_pair(%StateCycle{pres_r_share: r} = cycle) do
    %{
      cycle: cycle.cycle,
      r_vote: decimal1(r),
      d_vote: decimal1(100 - r),
      seats_rep: cycle.seats_rep,
      seats_dem: cycle.seats_dem,
      total: StateCycle.total_seats(cycle)
    }
  end

  # -- Least-compact district label -----------------------------------------

  def district_label(nil), do: nil

  def district_label(slug) do
    [state, number_part] = String.split(slug, "-", parts: 2)
    number = String.to_integer(number_part)
    state = String.upcase(state)
    if number == 0, do: "#{state}-AL", else: "#{state}-#{pad(number)}"
  end

  defp pad(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")

  defp decimal1(value), do: :erlang.float_to_binary(value / 1, decimals: 1)

  # -- History chart ---------------------------------------------------------

  @width 800
  @height 300
  @margin_x 52
  @margin_top 24
  @margin_bottom 44
  @plot_height @height - @margin_top - @margin_bottom
  @plot_width @width - 2 * @margin_x

  @doc """
  Server-rendered inline SVG for "Seats and votes since 1976": no JS, no
  chart library. Steps trace the Republican seat share every cycle;
  circles mark the Republican share of the two-party presidential vote in
  presidential years only; the yellow bar in each presidential year is the
  gap between the two. Every square and circle carries a CSS-hover tip
  (year, vote share, and seat split) pinned to the top edge so the chart
  answers "what is this mark" in place. Returns a safe iodata tuple, or
  nil for an empty series.
  """
  def chart_svg([]), do: nil

  def chart_svg(history) do
    n = length(history)

    points =
      history
      |> Enum.with_index()
      |> Enum.map(fn {cycle, index} -> point(cycle, index, n) end)

    bars = points |> Enum.filter(&(&1.vote_y && &1.seat_y)) |> Enum.map_join("", &bar_svg/1)
    step = step_path(points)
    squares = points |> Enum.filter(& &1.seat_y) |> Enum.map_join("", &square_svg/1)
    circles = points |> Enum.filter(& &1.vote_y) |> Enum.map_join("", &circle_svg/1)
    years = points |> Enum.filter(&(rem(&1.year, 8) == 0)) |> Enum.map_join("", &year_label_svg/1)
    rule_y = y_for(50)

    Phoenix.HTML.raw("""
    <svg viewBox="0 0 #{@width} #{@height}" role="img" aria-label="Seats and votes since 1976" class="state-history-chart">
      <line x1="#{@margin_x}" y1="#{fmt(rule_y)}" x2="#{@width - @margin_x}" y2="#{fmt(rule_y)}" stroke="var(--ink)" stroke-width="1" stroke-dasharray="4 4" />
      #{y_axis_svg()}
      #{years}
      #{bars}
      <path d="#{step}" fill="none" stroke="var(--ink)" stroke-width="2" />
      #{squares}
      #{circles}
    </svg>
    """)
  end

  defp point(cycle, index, n) do
    x =
      if n > 1,
        do: @margin_x + index * (@plot_width / (n - 1)),
        else: @margin_x + @plot_width / 2

    total = StateCycle.total_seats(cycle)
    seat_share = if total > 0, do: 100 * cycle.seats_rep / total
    vote_share = cycle.pres_r_share

    %{
      x: x,
      year: cycle.cycle,
      seats_rep: cycle.seats_rep,
      total: total,
      seat_share: seat_share,
      seat_y: seat_share && y_for(seat_share),
      vote_share: vote_share,
      vote_y: vote_share && y_for(vote_share)
    }
  end

  defp y_for(pct), do: @margin_top + (100 - pct) / 100 * @plot_height

  defp step_path([]), do: ""

  defp step_path([first | rest]) do
    build_step(["M#{fmt(first.x)} #{fmt(first.seat_y)}"], first, rest)
    |> Enum.join(" ")
  end

  defp build_step(acc, _prev, []), do: acc

  defp build_step(acc, prev, [point | rest]) do
    acc = acc ++ ["L#{fmt(point.x)} #{fmt(prev.seat_y)}", "L#{fmt(point.x)} #{fmt(point.seat_y)}"]
    build_step(acc, point, rest)
  end

  defp square_svg(%{x: x, seat_y: y} = point) do
    size = 6
    half = size / 2
    tip = tip_svg(x, tip_text(point))

    "<g class=\"chart-pt\">" <>
      hit_svg(x, y) <>
      "<rect x=\"#{fmt(x - half)}\" y=\"#{fmt(y - half)}\" width=\"#{size}\" height=\"#{size}\" fill=\"var(--ink)\" stroke=\"var(--ink)\" />" <>
      tip <> "</g>"
  end

  defp circle_svg(%{x: x, vote_y: y} = point) do
    tip = tip_svg(x, tip_text(point))

    "<g class=\"chart-pt\">" <>
      hit_svg(x, y) <>
      "<circle cx=\"#{fmt(x)}\" cy=\"#{fmt(y)}\" r=\"5\" fill=\"var(--paper)\" stroke=\"var(--ink)\" stroke-width=\"2\" />" <>
      tip <> "</g>"
  end

  # One combined readout per cycle — both marks tell the whole year's story.
  # Midterm squares have no presidential share, so they show seats alone.
  defp tip_text(%{year: year, vote_share: nil, seats_rep: r, total: total}),
    do: "#{year} · R seats #{r} of #{total}"

  defp tip_text(%{year: year, vote_share: vote, seats_rep: r, total: total}),
    do: "#{year} · R vote #{decimal1(vote)}% · R seats #{r} of #{total}"

  # Generous invisible hover target around each mark.
  defp hit_svg(x, y) do
    "<rect class=\"chart-hit\" x=\"#{fmt(x - 11)}\" y=\"#{fmt(y - 11)}\" width=\"22\" height=\"22\" fill=\"transparent\" />"
  end

  # Hover tip: hidden until the group is hovered (CSS). Pinned to the top
  # edge of the chart — mid-plot positions collide with marks and step lines.
  defp tip_svg(x, text) do
    tx = x |> max(@margin_x + 150.0) |> min(@width - @margin_x - 150.0)

    "<text class=\"chart-tip\" x=\"#{fmt(tx)}\" y=\"14\" text-anchor=\"middle\">#{text}</text>"
  end

  defp y_axis_svg do
    Enum.map_join([0, 50, 100], "", fn pct ->
      "<text class=\"chart-axis\" x=\"#{@margin_x - 10}\" y=\"#{fmt(y_for(pct) + 4)}\" text-anchor=\"end\">#{pct}%</text>"
    end)
  end

  defp year_label_svg(%{x: x, year: year}) do
    "<text class=\"chart-axis\" x=\"#{fmt(x)}\" y=\"#{@height - 12}\" text-anchor=\"middle\">#{year}</text>"
  end

  defp bar_svg(%{x: x, vote_y: vote_y, seat_y: seat_y}) do
    y1 = min(vote_y, seat_y)
    y2 = max(vote_y, seat_y)

    "<line x1=\"#{fmt(x)}\" y1=\"#{fmt(y1)}\" x2=\"#{fmt(x)}\" y2=\"#{fmt(y2)}\" stroke=\"var(--yellow)\" stroke-width=\"6\" />"
  end

  defp fmt(value), do: :erlang.float_to_binary(value / 1, decimals: 2)
end
