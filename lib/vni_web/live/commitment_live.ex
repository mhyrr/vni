defmodule VNIWeb.CommitmentLive do
  @moduledoc """
  Confirm a commitment, then manage or withdraw it.

  One durable token per pledge does both jobs — it is the magic link and
  the unsubscribe link, which is design 001 §5's no-accounts posture kept
  intact.

  Landing here confirms, and confirming is where the cross-pressure line
  lands. Because the commitment question comes before the party question,
  the hard sentence arrives as recognition of what someone just did rather
  than as a warning that might have stopped them doing it.
  """

  use VNIWeb, :live_view

  alias VNI.{Atlas, Pledges}
  alias VNIWeb.DistrictPresenter

  def mount(%{"token" => token}, _session, socket) do
    case Pledges.confirm(token) do
      {:error, :not_found} ->
        {:ok, assign(socket, page_title: "Link not found", pledge: nil, token: token)}

      {:ok, pledge} ->
        {:ok, assign_pledge(socket, pledge, token)}
    end
  end

  def handle_event("withdraw", _params, socket) do
    {:ok, pledge} = Pledges.withdraw(socket.assigns.token)
    {:noreply, assign_pledge(socket, pledge, socket.assigns.token)}
  end

  defp assign_pledge(socket, pledge, token) do
    district = Atlas.get_district!(pledge.district_id)
    presented = DistrictPresenter.present(district)
    count = Pledges.committed_count(pledge.district_id)

    assign(socket,
      page_title: "Your commitment · #{presented.label}",
      pledge: pledge,
      token: token,
      district: presented,
      count: count,
      target: Pledges.target(district.profile, count),
      recognition: recognition(pledge.party, presented.incumbent_party_key)
    )
  end

  @doc """
  What the screen says about the choice someone just made.

  `:against_own_party` is the project working. `:with_own_party` is the
  case that can quietly eat it — a Democrat committing to vote out a
  Republican is not anti-entrenchment, it is voting Democrat — so the copy
  says so rather than congratulating them for a free choice.
  """
  def recognition(party, incumbent) when party in [:republican, :democrat] do
    cond do
      same_party?(party, incumbent) -> :against_own_party
      incumbent in [:dem, :rep] -> :with_own_party
      true -> :neutral
    end
  end

  def recognition(_party, _incumbent), do: :neutral

  defp same_party?(:republican, :rep), do: true
  defp same_party?(:democrat, :dem), do: true
  defp same_party?(_, _), do: false
end
