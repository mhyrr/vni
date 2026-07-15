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
             :compactness -> Scores.list_least_compact(sort)
             :political -> Politics.list_most_entrenched(sort)
           end
           |> DistrictPresenter.present_field()

         {:ok, districts, reset: true}
       end,
       reset: true
     )}
  end

  defp resolve_sort(param) do
    cond do
      sort = @metric_sorts[param] -> {sort, :compactness}
      sort = @political_sorts[param] -> {sort, :political}
      true -> {:composite, :compactness}
    end
  end
end
