defmodule VNIWeb.FindLive do
  @moduledoc """
  Find your seat, from a ZIP code.

  A ZIP is not a district and the site does not pretend otherwise. Where
  the crosswalk resolves to one seat there is nothing to choose and the
  reader lands on it. Where a ZIP spans several, the choices are shown
  with their shapes and the reader picks — ordering by overlap is a
  convenience, never a selection.

  Showing the shapes is not decoration. It puts the gerrymander in front
  of someone before we have said a word about it.
  """

  use VNIWeb, :live_view

  alias VNI.Atlas.Postal
  alias VNIWeb.DistrictPresenter

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Find your district", zip: nil, matches: [])}
  end

  def handle_params(params, _uri, socket) do
    case params["zip"] do
      blank when blank in [nil, ""] ->
        {:noreply, assign(socket, state: :prompt, zip: nil, matches: [])}

      zip ->
        {:noreply, resolve(socket, zip)}
    end
  end

  defp resolve(socket, zip) do
    entered = String.trim(zip)

    case Postal.resolve(zip) do
      {:ok, [only]} ->
        # One seat is not a choice. Nothing is being picked for anyone.
        # `from=zip` marks the arrival as an answer to a question the
        # reader asked — see `VNIWeb.PublicComponents.commitment_prompt/1`.
        push_navigate(socket, to: ~p"/districts/#{only.district.slug}?from=zip")

      {:ok, matches} ->
        assign(socket,
          state: :choose,
          zip: normalized(zip, entered),
          matches: Enum.map(matches, &present/1)
        )

      {:error, reason} ->
        assign(socket, state: reason, zip: entered, matches: [])
    end
  end

  defp present(%{district: district} = match) do
    district
    |> DistrictPresenter.present()
    |> Map.put(:zcta_share, match.zcta_share)
    |> Map.put(:share_label, share_label(match.zcta_share))
  end

  # Rounded for reading, floored at "under 1%" so a sliver that survived
  # the rule never renders as a confident 0%.
  defp share_label(share) when share < 0.01, do: "under 1%"
  defp share_label(share), do: "#{round(share * 100)}%"

  defp normalized(zip, fallback) do
    case Postal.normalize(zip) do
      {:ok, zcta5} -> zcta5
      :error -> fallback
    end
  end
end
