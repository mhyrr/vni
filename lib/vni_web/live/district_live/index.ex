defmodule VNIWeb.DistrictLive.Index do
  use VNIWeb, :live_view

  alias VNI.Scores
  alias VNIWeb.DistrictPresenter

  @sorts %{
    "composite" => :composite,
    "polsby_popper" => :polsby_popper,
    "reock" => :reock,
    "convex_hull" => :convex_hull,
    "schwartzberg" => :schwartzberg
  }

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Districts", sort: :compactness)
     |> stream_configure(:districts, dom_id: &"district-#{&1.slug}")}
  end

  def handle_params(params, _uri, socket) do
    sort = Map.get(@sorts, params["sort"], :composite)

    {:noreply,
     socket
     |> assign(:sort, sort)
     |> stream_async(
       :districts,
       fn ->
         districts =
           sort
           |> Scores.list_least_compact()
           |> DistrictPresenter.present_field()

         {:ok, districts, reset: true}
       end,
       reset: true
     )}
  end
end
