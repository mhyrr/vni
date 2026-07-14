defmodule VNIWeb.DistrictLive.Show do
  use VNIWeb, :live_view

  alias VNI.Scores
  alias VNIWeb.DistrictPresenter

  def mount(%{"slug" => slug}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "#{String.upcase(slug)} district profile")
     |> assign_async(:district, fn ->
       case Scores.get_current_district(slug) do
         nil -> {:error, :not_found}
         district -> {:ok, %{district: DistrictPresenter.present(district)}}
       end
     end)}
  end
end
