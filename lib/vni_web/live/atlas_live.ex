defmodule VNIWeb.AtlasLive do
  use VNIWeb, :live_view

  alias VNIWeb.PreviewData

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "The Atlas")
     |> stream_configure(:districts, dom_id: &"district-#{&1.slug}")
     |> stream(:districts, PreviewData.all())}
  end
end
