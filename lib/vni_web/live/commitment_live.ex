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

  alias VNI.{Atlas, Pledges, Scores}
  alias VNIWeb.{DistrictPresenter, ShareCard}

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
    ranked_total = Scores.ranked_count_for_congress(district.map_version.congress)
    presented = DistrictPresenter.present(district, ranked_total)
    count = Pledges.committed_count(pledge.district_id)

    assign(socket,
      page_title: "Your commitment · #{presented.label}",
      pledge: pledge,
      token: token,
      district: presented,
      count: count,
      target: Pledges.target(district.profile, count),
      recognition: recognition(pledge.party, presented.incumbent_party_key),
      share: share(presented)
    )
  end

  @doc """
  Everything the share block needs, and nothing it must not have.

  The link is the district page, never this one. A commitment URL is a
  token, and a token in a post is the promise "we publish counts, never
  people" broken in the one place it would be broken in public — so it
  is absent here by construction rather than filtered later.
  """
  def share(district) do
    lines = ShareCard.lines(district)
    text = ShareCard.post_text()
    district_url = url(~p"/districts/#{district.slug}")

    %{
      lines: lines,
      text: text,
      url: district_url,
      filename: "vni-#{district.slug}.png",
      # Bare host, because the card prints where to go rather than a link
      # anyone taps. Reading it from the endpoint means it is right the
      # moment PHX_HOST changes and never needs the art rebuilt.
      host: VNIWeb.Endpoint.host(),
      intent: "https://x.com/intent/post?" <> URI.encode_query(%{text: text, url: district_url})
    }
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
