defmodule VNIWeb.MethodologyLive do
  use VNIWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Methodology")}
  end
end
