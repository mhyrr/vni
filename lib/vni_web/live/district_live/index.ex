defmodule VNIWeb.DistrictLive.Index do
  use VNIWeb, :live_view

  alias VNI.Politics
  alias VNI.Scores
  alias VNIWeb.{CongressTime, DistrictPresenter}

  @metric_sorts %{
    "composite" => :composite,
    "polsby_popper" => :polsby_popper,
    "reock" => :reock,
    "convex_hull" => :convex_hull,
    "schwartzberg" => :schwartzberg
  }

  @political_sorts %{
    "tenure" => :tenure,
    "margin" => :margin,
    "lean" => :lean
  }

  @bias_sorts %{"map_bias" => :map_bias}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Districts",
       sort: :composite,
       sort_kind: :compactness,
       congress: CongressTime.current_congress(),
       qualified?: false
     )
     |> stream_configure(:districts, dom_id: &"district-#{&1.slug}")}
  end

  def handle_params(params, _uri, socket) do
    case CongressTime.resolve(params["congress"]) do
      :error ->
        {:noreply,
         socket
         |> put_flash(:error, "That Congress is not available in the Atlas.")
         |> redirect(to: ~p"/districts")}

      {:ok, congress, qualified?} ->
        current? = congress == CongressTime.current_congress()
        {sort, sort_kind} = resolve_sort(params["sort"], current?)
        base_path = CongressTime.page_path(:districts, congress, nil, qualified?)

        {:noreply,
         socket
         |> assign(
           congress: congress,
           qualified?: qualified?,
           current?: current?,
           sort: sort,
           sort_kind: sort_kind,
           district_base_path: base_path,
           time_context: CongressTime.context(congress, :districts),
           sort_paths: sort_paths(base_path)
         )
         |> stream_async(
           :districts,
           fn ->
             districts = list_districts(congress, current?, sort, sort_kind)
             {:ok, districts, reset: true}
           end,
           reset: true
         )}
    end
  end

  defp resolve_sort(param, current?) do
    cond do
      sort = @metric_sorts[param] -> {sort, :compactness}
      current? && Map.has_key?(@political_sorts, param) -> {@political_sorts[param], :political}
      current? && Map.has_key?(@bias_sorts, param) -> {@bias_sorts[param], :map_bias}
      true -> {:composite, :compactness}
    end
  end

  defp list_districts(congress, _current?, sort, :compactness) do
    congress
    |> Scores.list_least_compact_for_congress(sort)
    |> DistrictPresenter.present_field()
  end

  defp list_districts(_congress, true, sort, :political) do
    Politics.list_most_entrenched(sort) |> DistrictPresenter.present_field()
  end

  defp list_districts(_congress, true, _sort, :map_bias), do: list_by_map_bias()

  defp sort_paths(base_path) do
    ((@metric_sorts |> Map.keys()) ++
       (@political_sorts |> Map.keys()) ++ (@bias_sorts |> Map.keys()))
    |> Map.new(fn sort -> {sort, CongressTime.with_query(base_path, sort: sort)} end)
  end

  # The map-skew sort carries each district's statewide gap onto the
  # card: presenter maps stay the interface, the state's skew string is
  # merged in by position (list order is preserved by present_field).
  defp list_by_map_bias do
    districts = Scores.StateBias.list_districts_by_skew()
    skews = VNIWeb.StatePresenter.skew_by_state()

    districts
    |> DistrictPresenter.present_field()
    |> Enum.zip_with(districts, fn presented, district ->
      Map.put(presented, :state_skew, skews[district.state])
    end)
  end
end
