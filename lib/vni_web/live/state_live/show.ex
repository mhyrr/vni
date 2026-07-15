defmodule VNIWeb.StateLive.Show do
  use VNIWeb, :live_view

  alias VNI.Politics
  alias VNI.Scores
  alias VNI.Scores.StateBias
  alias VNIWeb.{DistrictPresenter, StatePresenter}

  def mount(%{"state" => state_param}, _session, socket) do
    state = String.upcase(state_param)

    case StateBias.state_row(state) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "That state isn't in the current map set.")
         |> redirect(to: ~p"/states")}

      row ->
        cycle = Politics.latest_state_cycles()[state]
        history = Politics.state_history(state)
        ranked_total = Scores.ranked_count()

        districts =
          state
          |> Scores.list_state_districts()
          |> Enum.map(&DistrictPresenter.present(&1, ranked_total))

        {:ok,
         assign(socket,
           page_title: "#{StatePresenter.state_name(state)} · state map",
           state: StatePresenter.present_show(row, cycle, history),
           districts: districts,
           methodology_version: Scores.methodology_version(),
           mean_median_seat_floor: StateBias.mean_median_seat_floor()
         )}
    end
  end
end
