defmodule VNIWeb.DistrictLive.Index do
  use VNIWeb, :live_view

  alias VNI.Politics
  alias VNI.Scores
  alias VNIWeb.DistrictPresenter

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
     |> assign(page_title: "Districts", sort: :composite, sort_kind: :compactness)
     |> stream_configure(:districts, dom_id: &"district-#{&1.slug}")}
  end

  def handle_params(params, _uri, socket) do
    {sort, sort_kind} = resolve_sort(params["sort"])

    {:noreply,
     socket
     |> assign(sort: sort, sort_kind: sort_kind)
     |> stream_async(
       :districts,
       fn ->
         districts =
           case sort_kind do
             :compactness ->
               Scores.list_least_compact(sort) |> DistrictPresenter.present_field()

             :political ->
               Politics.list_most_entrenched(sort) |> DistrictPresenter.present_field()

             :map_bias ->
               list_by_map_bias()
           end

         {:ok, districts, reset: true}
       end,
       reset: true
     )}
  end

  defp resolve_sort(param) do
    cond do
      sort = @metric_sorts[param] -> {sort, :compactness}
      sort = @political_sorts[param] -> {sort, :political}
      sort = @bias_sorts[param] -> {sort, :map_bias}
      true -> {:composite, :compactness}
    end
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
