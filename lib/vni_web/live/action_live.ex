defmodule VNIWeb.ActionLive do
  use VNIWeb, :live_view

  @answers ~w(yes maybe no)

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Cross the line", answer: nil)}
  end

  def handle_event("answer", %{"answer" => answer}, socket) when answer in @answers do
    {:noreply, assign(socket, :answer, answer)}
  end
end
