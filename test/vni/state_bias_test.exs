defmodule VNI.Scores.StateBiasTest do
  use VNI.DataCase, async: true

  alias VNI.{Atlas, Politics, Repo}
  alias VNI.Scores.DistrictScore
  alias VNI.Scores.StateBias

  defp create_state!(state, shares, opts \\ []) do
    {:ok, mv} =
      Atlas.create_map_version(%{
        state: state,
        level: :congressional,
        congress: 119,
        effective_from: ~D[2025-01-03],
        authority: Keyword.get(opts, :authority),
        controlling_party: Keyword.get(opts, :controlling_party)
      })

    at_large? = length(shares) == 1

    for {share, i} <- Enum.with_index(shares) do
      number = if at_large?, do: 0, else: i + 1
      {:ok, district} = Atlas.upsert_district(mv, %{state: state, number: number})

      if share do
        {:ok, _} = Politics.upsert_profile(district, %{pres_share_2024: share})
      end

      district
    end
  end

  defp score!(district, composite, rank) do
    Repo.insert!(%DistrictScore{
      district_id: district.id,
      composite: composite,
      national_rank: rank,
      methodology_version: "test"
    })
  end

  test "mean-median: floored, sign matches lean, partial data publishes nothing" do
    # 5 seats, complete shares: median (56) minus mean (53.6) = +2.4,
    # positive = the median district is redder than the state average.
    create_state!("SC", [40.0, 55.0, 56.0, 57.0, 60.0], authority: :legislature)
    # 4 seats: below the floor even with complete shares.
    create_state!("UT", [55.0, 56.0, 57.0, 58.0])
    # 5 seats but one share missing: no partial statistic.
    create_state!("NC", [40.0, 50.0, 55.0, 60.0, nil])
    # At-large: one district, number 0.
    create_state!("WY", [70.0])

    rows = Map.new(StateBias.state_rows(), &{&1.state, &1})

    assert_in_delta rows["SC"].mean_median, 2.4, 0.0001
    assert rows["SC"].seats == 5
    assert rows["SC"].at_large == false
    assert rows["SC"].authority == :legislature

    assert rows["UT"].mean_median == nil
    assert rows["UT"].seats == 4

    assert rows["NC"].mean_median == nil

    assert rows["WY"].at_large == true
    assert rows["WY"].seats == 1
    assert rows["WY"].mean_median == nil
  end

  test "two districts: the median is the mean, the statistic is blind" do
    # The floor exists because this is identically zero, not because we
    # chose not to publish it — with the floor at 2 it would print 0.0
    # for every 2-seat state regardless of how the lines are drawn.
    create_state!("NH", [30.0, 70.0])

    row = StateBias.state_row("NH")
    assert row.mean_median == nil
    assert row.seats == 2
  end

  test "worst district and compactness aggregates" do
    [d1, d2, d3, d4, d5] = create_state!("SC", [40.0, 55.0, 56.0, 57.0, 60.0])
    score!(d1, 0.8, 10)
    score!(d2, 0.6, 100)
    score!(d3, 0.5, 200)
    score!(d4, 0.4, 300)
    score!(d5, 0.2, 420)

    row = StateBias.state_row("SC")
    assert row.worst_district_slug == d5.slug
    assert row.worst_district_rank == 420
    assert_in_delta row.mean_composite, 0.5, 0.0001
    assert_in_delta row.median_composite, 0.5, 0.0001
  end
end
