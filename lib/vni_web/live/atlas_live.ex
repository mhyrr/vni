defmodule VNIWeb.AtlasLive do
  use VNIWeb, :live_view

  alias VNI.Scores
  alias VNIWeb.DistrictPresenter

  @color_modes %{"compactness" => :compactness, "lean" => :lean}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "The Atlas")
     |> stream_configure(:districts, dom_id: &"district-#{&1.slug}")}
  end

  def handle_params(params, _uri, socket) do
    color_by = Map.get(@color_modes, params["color"], :compactness)

    {:noreply,
     socket
     |> assign(:color_by, color_by)
     |> stream_async(
       :districts,
       fn ->
         districts =
           :composite
           |> Scores.list_least_compact()
           |> DistrictPresenter.present_field()

         {:ok, districts, reset: true}
       end,
       reset: true
     )}
  end
end
