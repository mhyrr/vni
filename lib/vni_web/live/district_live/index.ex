defmodule VNIWeb.DistrictLive.Index do
  use VNIWeb, :live_view

  alias VNIWeb.PreviewData

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Districts", sort: :compactness)
     |> stream_configure(:districts, dom_id: &"district-#{&1.slug}")}
  end

  def handle_params(params, _uri, socket) do
    sort = PreviewData.parse_sort(params["sort"])

    {:noreply,
     socket
     |> assign(:sort, sort)
     |> stream(:districts, PreviewData.sort(sort), reset: true)}
  end
end
