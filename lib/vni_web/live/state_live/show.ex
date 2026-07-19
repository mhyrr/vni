defmodule VNIWeb.StateLive.Show do
  use VNIWeb, :live_view

  alias VNI.Politics
  alias VNI.Scores
  alias VNI.Scores.StateBias
  alias VNIWeb.{CongressTime, DistrictPresenter, StatePresenter}

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(%{"state" => state_param} = params, _uri, socket) do
    state = String.upcase(state_param)

    with {:ok, congress, qualified?} <- CongressTime.resolve(params["congress"]),
         row when not is_nil(row) <- StateBias.state_row_for_congress(state, congress) do
      cycle = Politics.latest_state_cycles()[state]
      history = Politics.state_history(state)
      ranked_total = Scores.ranked_count_for_congress(congress)

      districts =
        state
        |> Scores.list_state_districts_for_congress(congress)
        |> Enum.map(&DistrictPresenter.present(&1, ranked_total))

      {:noreply,
       assign(socket,
         page_title: "#{StatePresenter.state_name(state)} · #{congress}th Congress map",
         congress: congress,
         qualified?: qualified?,
         current?: congress == CongressTime.current_congress(),
         time_context: CongressTime.context(congress, :state, String.downcase(state)),
         map_continuity: CongressTime.map_continuity(congress, state, row.at_large),
         state_index_path: CongressTime.page_path(:states, congress, nil, qualified?),
         district_base_path: CongressTime.page_path(:districts, congress, nil, qualified?),
         state: StatePresenter.present_show(row, cycle, history),
         districts: districts,
         lean_strip: StatePresenter.lean_strip_svg(districts),
         methodology_version: Scores.methodology_version(),
         mean_median_seat_floor: StateBias.mean_median_seat_floor()
       )}
    else
      _not_found ->
        fallback =
          case CongressTime.resolve(params["congress"]) do
            {:ok, congress, qualified?} ->
              CongressTime.page_path(:states, congress, nil, qualified?)

            :error ->
              ~p"/states"
          end

        {:noreply,
         socket
         |> put_flash(:error, "That state isn't in the selected Congress's map set.")
         |> redirect(to: fallback)}
    end
  end
end
