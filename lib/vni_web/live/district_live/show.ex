defmodule VNIWeb.DistrictLive.Show do
  @moduledoc """
  One seat's file: the shape, the scores, the incumbent, and the ask.

  The commitment block renders only under the current map. The historical
  lens is geometry that no longer governs anyone — there is nobody to
  vote against in the 117th, and a count attached to a retired district
  would be a number about nothing.
  """

  use VNIWeb, :live_view

  alias VNI.{Atlas, Pledges, Scores}
  alias VNIWeb.{CongressTime, DistrictPresenter, SocialMeta}

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
        current? = congress == CongressTime.current_congress()

        {:noreply,
         socket
         |> assign(
           page_title: "#{String.upcase(slug)} · #{congress}th Congress",
           congress: congress,
           qualified?: qualified?,
           current?: current?,
           index_path: index_path,
           time_context: CongressTime.context(congress, :district, slug),
           og_image: SocialMeta.district_image(slug, current?)
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
                 |> Map.merge(commitment(district, current?))

               {:ok, %{district: presented}}
           end
         end)}
    end
  end

  # The count, its split, and the rung being climbed. Queried only under
  # the current map — a historical district has no live count to report
  # and asking for one is a query about nothing.
  defp commitment(district, true = _current?) do
    counts = Pledges.district_counts(district.id)
    target = Pledges.target(district.profile, counts.committed)

    %{
      commitment_counts: counts,
      commitment_count: counts.committed,
      commitment_count_label: DistrictPresenter.number(counts.committed),
      commitment_target: target,
      commitment_target_label: DistrictPresenter.number(target),
      commitment_progress: progress(counts.committed, target)
    }
  end

  defp commitment(_district, _historical) do
    %{
      commitment_counts: nil,
      commitment_count: nil,
      commitment_count_label: nil,
      commitment_target: nil,
      commitment_target_label: nil,
      commitment_progress: nil
    }
  end

  # Capped at the rung, because a count can pass a target between the
  # moment it is chosen and the moment the next one is.
  defp progress(count, target) when is_integer(target) and target > 0 do
    (count / target * 100) |> min(100.0) |> Float.round(1)
  end
end
