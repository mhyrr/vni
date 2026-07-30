defmodule VNIWeb.ShareCard do
  @moduledoc """
  The words on a shareable artifact, in one place.

  Two surfaces carry a district off the site — the 1080×1920 story card
  drawn on canvas at `/commitment/:token`, and the 1200×630 unfurl image
  baked by `mix vni.og.cards`. Both say the same things, and keeping the
  branch table here is what stops them drifting into two voices.

  The fact line reuses `VNI.Pledges.goal_basis/1` rather than inventing a
  fourth copy path. A margin is stated here as a fact about the seat,
  never as a goal: "decided by 214,309 votes" under "held 22 years" reads
  as a fortress, which is the argument. The same number offered as a bar
  to clear would read as a wall, which is why the district page shows a
  reachable rung from `Pledges.target/2` instead.

  Nothing in this module accepts a token. The site publishes counts and
  never people, and a shared artifact is the one place that promise is
  tested in public — so there is no argument here that could carry one.
  """

  @doc """
  The three lines on a card: the seat, a headline, and a fact.

  Tenure is the headline wherever there is an incumbent, because it is
  the anti-entrenchment fact and it is legible to a stranger who has
  never heard of the person holding the seat. Rank is the understudy —
  it steps into whichever slot tenure or the margin left empty, and
  never into both.

  `:headline` and `:fact` are each nil-able. An at-large seat with a
  vacancy has neither: at-large districts carry no national rank
  (methodology 2026.2), and a vacancy carries no tenure.
  """
  def lines(district) do
    {headline, fact} =
      case {tenure_headline(district), fact_line(district)} do
        {nil, fact} -> {rank_headline(district), fact}
        {tenure, nil} -> {tenure, rank_fact(district)}
        {tenure, fact} -> {tenure, fact}
      end

    %{label: district.label, headline: headline, fact: fact}
  end

  @doc """
  The sentence someone posts, built from the same facts as the card.

  Ends on the site's own line about what was committed to — "the person
  holding this seat, whoever runs against them" — which is the phrasing
  that survives a vacancy and keeps the claim about the seat rather than
  about a named person.
  """
  def post_text(district) do
    case facts_sentence(district) do
      nil ->
        "I've committed to vote against the person holding #{district.label}, " <>
          "whoever runs against them."

      sentence ->
        sentence <>
          " I've committed to vote against the person holding this seat, " <>
          "whoever runs against them."
    end
  end

  ## Card lines

  defp tenure_headline(district) do
    case tenure_years(district) do
      nil -> nil
      years -> "HELD #{String.upcase(years_phrase(years))}"
    end
  end

  defp fact_line(%{commitment_goal_basis: :unopposed}), do: "Nobody ran against this seat."

  defp fact_line(%{commitment_goal_basis: :margin} = district),
    do: "Decided by #{district.last_margin_votes} votes#{cycle(district)}."

  defp fact_line(_unknown_basis), do: nil

  defp rank_headline(%{national_rank: nil}), do: nil
  defp rank_headline(%{national_rank: rank, ranked_total: nil}), do: "RANK #{rank}"
  defp rank_headline(%{national_rank: rank, ranked_total: total}), do: "RANK #{rank} / #{total}"

  defp rank_fact(%{national_rank: nil}), do: nil

  defp rank_fact(%{national_rank: rank, ranked_total: nil}),
    do: "Rank #{rank} for compactness."

  defp rank_fact(%{national_rank: rank, ranked_total: total}),
    do: "Rank #{rank} of #{total} for compactness."

  ## Post text

  defp facts_sentence(district) do
    years = tenure_years(district)
    basis = district.commitment_goal_basis

    cond do
      years && basis == :unopposed ->
        "#{district.label} has been held #{years_phrase(years)}, " <>
          "and nobody ran against it#{cycle(district)}."

      years && basis == :margin ->
        "#{district.label} has been held #{years_phrase(years)} and was decided by " <>
          "#{district.last_margin_votes} votes#{cycle(district)}."

      years ->
        "#{district.label} has been held #{years_phrase(years)}."

      basis == :unopposed ->
        "Nobody ran against #{district.label}#{cycle(district)}."

      basis == :margin ->
        "#{district.label} was decided by #{district.last_margin_votes} votes#{cycle(district)}."

      true ->
        nil
    end
  end

  ## Shared

  # A seat won this year has been "held 0 years", which is true and says
  # nothing. Tenure starts carrying the card at one.
  defp tenure_years(%{incumbent_tenure: years}) when is_integer(years) and years >= 1, do: years
  defp tenure_years(_none_or_first_term), do: nil

  defp years_phrase(1), do: "1 year"
  defp years_phrase(years), do: "#{years} years"

  defp cycle(%{last_margin_cycle: nil}), do: ""
  defp cycle(%{last_margin_cycle: cycle}), do: " in #{cycle}"
end
