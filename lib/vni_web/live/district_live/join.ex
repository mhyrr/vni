defmodule VNIWeb.DistrictLive.Join do
  @moduledoc """
  The ask, for one seat.

  Three questions and an address, on one screen. The commitment comes
  first because it is the most important thing and you do not qualify
  someone before asking it — the ask is already specific without their
  answers, because the incumbent is a published fact.

  Only the current Congress can be committed to. The historical lens
  (`/congresses/:congress/...`) is a view of geometry that no longer
  governs anyone; there is nobody to vote against in the 117th.
  """

  use VNIWeb, :live_view

  alias VNI.{Pledges, Scores}
  alias VNI.Pledges.Notifier
  alias VNIWeb.{CongressTime, DistrictPresenter}

  def mount(%{"slug" => slug}, _session, socket) do
    congress = CongressTime.current_congress()

    case Scores.get_district_for_congress(slug, congress) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "No such district.")
         |> redirect(to: ~p"/districts")}

      district ->
        presented = DistrictPresenter.present(district)

        {:ok,
         socket
         |> assign(
           page_title: "Commit · #{String.upcase(slug)}",
           district: presented,
           district_id: district.id,
           count: Pledges.committed_count(district.id),
           target: Pledges.target(district.profile, Pledges.committed_count(district.id)),
           params: %{},
           errors: %{},
           sent_to: nil
         )}
    end
  end

  # Selection state only — the answers are validated on submit, so a
  # half-filled form never scolds anyone mid-thought.
  def handle_event("validate", %{"commitment" => params}, socket) do
    {:noreply, assign(socket, :params, params)}
  end

  def handle_event("submit", %{"commitment" => params}, socket) do
    district = %VNI.Atlas.District{id: socket.assigns.district_id}

    case Pledges.record(district, params) do
      {:ok, :already_confirmed, pledge, token} ->
        Notifier.deliver_recovery(pledge.email, seat_label(socket), url(~p"/commitment/#{token}"))
        {:noreply, assign(socket, sent_to: pledge.email, errors: %{})}

      {:ok, _created_or_reissued, pledge, token} ->
        Notifier.deliver_confirmation(
          pledge.email,
          seat_label(socket),
          incumbent(socket),
          url(~p"/commitment/#{token}")
        )

        {:noreply, assign(socket, sent_to: pledge.email, errors: %{})}

      {:error, :disposable_email} ->
        {:noreply,
         assign(socket,
           errors: %{email: "Use an address you can actually receive mail at."},
           params: params
         )}

      {:error, changeset} ->
        {:noreply,
         assign(socket,
           errors: error_map(changeset),
           params: params
         )}
    end
  end

  defp error_map(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Map.new(fn {field, [msg | _]} -> {field, String.capitalize(msg) <> "."} end)
  end

  defp seat_label(socket), do: socket.assigns.district.label
  defp incumbent(socket), do: socket.assigns.district.incumbent_name || "this seat's incumbent"
end
