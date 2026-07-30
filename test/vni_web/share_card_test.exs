defmodule VNIWeb.ShareCardTest do
  @moduledoc """
  The branch table, exercised without a database.

  `ShareCard` consumes a presented district and returns strings, so the
  fixtures here are presenter-shaped maps. That is deliberate: the copy
  paths are what break, and they break on shapes real data produces —
  a vacancy with no tenure, an at-large seat with no rank, a seat nobody
  contested.
  """

  use ExUnit.Case, async: true

  alias VNIWeb.ShareCard

  defp district(overrides \\ %{}) do
    Map.merge(
      %{
        label: "OH-09",
        incumbent_tenure: 43,
        commitment_goal_basis: :margin,
        last_margin_votes: "2,382",
        last_margin_cycle: 2024,
        national_rank: 412,
        ranked_total: 429
      },
      overrides
    )
  end

  describe "lines/1" do
    test "leads on tenure and states the margin as a fact about the seat" do
      assert %{
               label: "OH-09",
               headline: "HELD 43 YEARS",
               fact: "Decided by 2,382 votes in 2024."
             } = ShareCard.lines(district())
    end

    test "a big margin is not softened — the fortress is the argument" do
      lines = ShareCard.lines(district(%{incumbent_tenure: 22, last_margin_votes: "214,309"}))

      assert lines.headline == "HELD 22 YEARS"
      assert lines.fact == "Decided by 214,309 votes in 2024."
    end

    test "an unopposed seat says so instead of quoting the winner's whole vote total" do
      lines = ShareCard.lines(district(%{commitment_goal_basis: :unopposed}))

      assert lines.fact == "Nobody ran against this seat."
    end

    test "a vacancy has no tenure, so rank takes the headline" do
      lines = ShareCard.lines(district(%{incumbent_tenure: nil}))

      assert lines.headline == "RANK 412 / 429"
      assert lines.fact == "Decided by 2,382 votes in 2024."
    end

    test "an unknown margin basis hands the fact line to rank" do
      lines = ShareCard.lines(district(%{commitment_goal_basis: :unknown}))

      assert lines.headline == "HELD 43 YEARS"
      assert lines.fact == "Rank 412 of 429 for compactness."
    end

    test "rank never fills both slots at once" do
      lines =
        ShareCard.lines(district(%{incumbent_tenure: nil, commitment_goal_basis: :unknown}))

      assert lines.headline == "RANK 412 / 429"
      assert lines.fact == nil
    end

    test "an at-large vacancy carries neither — at-large seats are unranked" do
      lines =
        ShareCard.lines(
          district(%{
            label: "AK-AL",
            incumbent_tenure: nil,
            commitment_goal_basis: :unknown,
            national_rank: nil,
            ranked_total: nil
          })
        )

      assert lines == %{label: "AK-AL", headline: nil, fact: nil}
    end

    test "a first-term seat drops tenure rather than claiming zero years" do
      lines = ShareCard.lines(district(%{incumbent_tenure: 0}))

      assert lines.headline == "RANK 412 / 429"
    end

    test "one year is singular" do
      lines = ShareCard.lines(district(%{incumbent_tenure: 1}))

      assert lines.headline == "HELD 1 YEAR"
    end

    test "rank drops the denominator when the presented field did not count one" do
      lines = ShareCard.lines(district(%{incumbent_tenure: nil, ranked_total: nil}))

      assert lines.headline == "RANK 412"
    end

    test "a missing cycle drops the year rather than printing an empty one" do
      lines = ShareCard.lines(district(%{last_margin_cycle: nil}))

      assert lines.fact == "Decided by 2,382 votes."
    end
  end

  describe "post_text/0" do
    test "makes the argument rather than restating the picture beside it" do
      text = ShareCard.post_text()

      assert text =~ "Everyone hates Congress but incumbents still win."
      assert text =~ "I've committed to vote against my incumbent"
      assert text =~ "anyone new is better than the entrenched power we have"
    end

    # Premium accounts take 25,000 characters, but a free one is still
    # capped at 280 and that is who this has to work for. Any link costs
    # 23 of them however long it is, plus the space before it. Going over
    # does not truncate — it hands the person a composer they have to
    # edit before it will post.
    test "fits a free X account with a link attached" do
      assert String.length(ShareCard.post_text()) + 24 <= 280
    end

    test "carries no district facts — the card that travels with it has them" do
      text = ShareCard.post_text()

      refute text =~ "held"
      refute text =~ "Decided"
      refute text =~ "Rank"
    end

    test "names no one" do
      refute ShareCard.post_text() =~ ~r/[A-Z][a-z]+ [A-Z][a-z]+/
    end
  end
end
