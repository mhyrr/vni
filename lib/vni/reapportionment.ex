defmodule VNI.Reapportionment do
  @moduledoc """
  Huntington-Hill (method of equal proportions) — the actual algorithm the
  Census Bureau uses to apportion the House. Pure math over state population
  counts; feed it Census annual estimates to project the post-2030 map.

  Each state gets one seat, then remaining seats go one at a time to the
  state with the highest priority value P / sqrt(n(n+1)), where n is the
  state's current seat count.
  """

  @house_seats 435

  @doc """
  Apportion `total_seats` across states.

  `populations` is a map of state code => apportionment population,
  e.g. `%{"TX" => 29_183_290, ...}`. Returns state code => seats.
  """
  def apportion(populations, total_seats \\ @house_seats)
      when map_size(populations) > 0 and map_size(populations) <= total_seats do
    base = Map.new(populations, fn {state, _pop} -> {state, 1} end)
    remaining = total_seats - map_size(populations)

    Enum.reduce(1..remaining//1, base, fn _seat, seats ->
      {state, _n} = Enum.max_by(seats, fn {state, n} -> priority(populations[state], n) end)
      Map.update!(seats, state, &(&1 + 1))
    end)
  end

  @doc """
  Seat deltas between two apportionments: `%{"TX" => +2, "CA" => -1, ...}`.
  States with no change are omitted.
  """
  def changes(old, new) do
    for {state, seats} <- new,
        delta = seats - Map.get(old, state, 0),
        delta != 0,
        into: %{} do
      {state, delta}
    end
  end

  defp priority(pop, n), do: pop / :math.sqrt(n * (n + 1))
end
