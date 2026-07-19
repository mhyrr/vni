defmodule VNIWeb.DistrictLive.Show do
  use VNIWeb, :live_view

  alias VNI.{Atlas, Scores}
  alias VNIWeb.{CongressTime, DistrictPresenter}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:congress, CongressTime.current_congress())
     |> assign(:qualified?, false)}
  end

  def handle_params(%{"slug" => slug} = params, _uri, socket) do
    case CongressTime.resolve(params["congress"]) do
      :error ->
        {:noreply,
         socket
         |> put_flash(:error, "That Congress is not available in the Atlas.")
         |> redirect(to: ~p"/districts")}

      {:ok, congress, qualified?} ->
        index_path = CongressTime.page_path(:districts, congress, nil, qualified?)

        {:noreply,
         socket
         |> assign(
           page_title: "#{String.upcase(slug)} · #{congress}th Congress",
           congress: congress,
           qualified?: qualified?,
           index_path: index_path,
           time_context: CongressTime.context(congress, :district, slug)
         )
         |> assign_async(:district, fn ->
           case Scores.get_district_for_congress(slug, congress) do
             nil ->
               {:error, :not_found}

             district ->
               ranked_total = Scores.ranked_count_for_congress(congress)
               siblings = Atlas.list_sibling_geometries(district)

               presented =
                 district
                 |> DistrictPresenter.present(ranked_total)
                 |> Map.put(
                   :map_continuity,
                   CongressTime.map_continuity(congress, district.state, district.number == 0)
                 )
                 |> Map.put(
                   :state_context,
                   DistrictPresenter.state_context(district.geom_simplified, siblings)
                 )
                 |> Map.put(:state_seats, length(siblings) + 1)

               {:ok, %{district: presented}}
           end
         end)}
    end
  end
end
