defmodule VNIWeb.HomeLive do
  use VNIWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Vote No Incumbents")}
  end
end
