defmodule VNIWeb.AtlasLive do
  use VNIWeb, :live_view

  alias VNI.Scores
  alias VNIWeb.DistrictPresenter

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "The Atlas")
     |> stream_configure(:districts, dom_id: &"district-#{&1.slug}")
     |> stream_async(:districts, fn ->
       districts =
         :composite
         |> Scores.list_least_compact()
         |> DistrictPresenter.present_field()

       {:ok, districts}
     end)}
  end
end
