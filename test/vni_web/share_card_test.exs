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

  describe "post_text/1" do
    test "states the seat's facts, then what was committed to" do
      assert ShareCard.post_text(district()) ==
               "OH-09 has been held 43 years and was decided by 2,382 votes in 2024. " <>
                 "I've committed to vote against the person holding this seat, " <>
                 "whoever runs against them."
    end

    test "an unopposed seat reads as a sentence, not a caption" do
      text = ShareCard.post_text(district(%{commitment_goal_basis: :unopposed}))

      assert text =~ "OH-09 has been held 43 years, and nobody ran against it in 2024."
    end

    test "a vacancy keeps the margin and drops the tenure clause" do
      text = ShareCard.post_text(district(%{incumbent_tenure: nil}))

      assert text =~ "OH-09 was decided by 2,382 votes in 2024."
      refute text =~ "held"
    end

    test "an unopposed vacancy names the seat in the unopposed clause" do
      text =
        ShareCard.post_text(district(%{incumbent_tenure: nil, commitment_goal_basis: :unopposed}))

      assert text =~ "Nobody ran against OH-09 in 2024."
    end

    test "with no facts at all, the seat moves into the commitment sentence" do
      text =
        ShareCard.post_text(district(%{incumbent_tenure: nil, commitment_goal_basis: :unknown}))

      assert text ==
               "I've committed to vote against the person holding OH-09, " <>
                 "whoever runs against them."
    end

    test "never names the incumbent — the argument is about the seat" do
      text = ShareCard.post_text(district())

      refute text =~ "incumbent"
    end

    test "fits X's limit with room for a URL, even at the longest branch" do
      text =
        ShareCard.post_text(
          district(%{label: "MA-09", incumbent_tenure: 43, last_margin_votes: "214,309"})
        )

      assert String.length(text) <= 200
    end
  end
end
