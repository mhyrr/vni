defmodule VNIWeb.DistrictLive.Show do
  use VNIWeb, :live_view

  alias VNIWeb.PreviewData

  def mount(%{"slug" => slug}, _session, socket) do
    case PreviewData.get(slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "District not found")
         |> push_navigate(to: ~p"/districts")}

      district ->
        {:ok,
         assign(socket,
           page_title: "#{district.label} district profile",
           district: district
         )}
    end
  end
end
