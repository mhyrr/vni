defmodule VNI.ScoresTest do
  use VNI.DataCase, async: true

  alias VNI.Atlas
  alias VNI.Scores

  # A compact square and a thin C-shaped hook near the equator.
  # Polsby-Popper for a square is π/4 ≈ 0.785. The hook must be
  # non-convex — a thin rectangle would tie the square on convex hull
  # (a rectangle is its own hull) — so it loses on every metric.
  setup do
    {:ok, mv} =
      Atlas.create_map_version(%{
        state: "TX",
        level: :congressional,
        congress: 119,
        effective_from: ~D[2023-01-03]
      })

    {:ok, square} = Atlas.upsert_district(mv, %{state: "TX", number: 1, geom: square_geom()})
    {:ok, hook} = Atlas.upsert_district(mv, %{state: "TX", number: 2, geom: hook_geom()})

    {:ok, wy_mv} =
      Atlas.create_map_version(%{
        state: "WY",
        level: :congressional,
        congress: 119,
        effective_from: ~D[2023-01-03]
      })

    {:ok, at_large} =
      Atlas.upsert_district(wy_mv, %{state: "WY", number: 0, geom: square_geom()})

    %{map_version: mv, square: square, hook: hook, at_large: at_large}
  end

  defp square_geom do
    %Geo.MultiPolygon{
      coordinates: [[[{0.0, 0.0}, {0.2, 0.0}, {0.2, 0.2}, {0.0, 0.2}, {0.0, 0.0}]]],
      srid: 4326
    }
  end

  defp hook_geom do
    %Geo.MultiPolygon{
      coordinates: [
        [
          [
            {1.0, 0.0},
            {2.0, 0.0},
            {2.0, 0.05},
            {1.05, 0.05},
            {1.05, 0.95},
            {2.0, 0.95},
            {2.0, 1.0},
            {1.0, 1.0},
            {1.0, 0.0}
          ]
        ]
      ],
      srid: 4326
    }
  end

  test "raw metrics land in [0,1] and order compact above contorted", ctx do
    :ok = Scores.compute_metrics!(ctx.map_version.id)

    square = Scores.get_score(ctx.square.id)
    hook = Scores.get_score(ctx.hook.id)

    assert_in_delta square.polsby_popper, :math.pi() / 4, 0.02

    for metric <- [:polsby_popper, :reock, :convex_hull, :schwartzberg] do
      s = Map.fetch!(square, metric)
      r = Map.fetch!(hook, metric)

      assert s > 0.0 and s <= 1.0, "square #{metric} out of range: #{s}"
      assert r > 0.0 and r <= 1.0, "hook #{metric} out of range: #{r}"
      assert s > r, "expected square to beat hook on #{metric}"
    end

    assert square.methodology_version == Scores.methodology_version()
  end

  test "full scoring pass assigns composite and national rank", ctx do
    :ok = Scores.score_current!(:congressional)

    [first, second] = Scores.list_ranked(:congressional)

    assert first.id == ctx.square.id
    assert first.score.national_rank == 1
    assert second.id == ctx.hook.id
    assert second.score.national_rank == 2
    assert first.score.composite > second.score.composite
    assert Scores.ranked_count(:congressional) == 2

    [least_compact, most_compact, unranked] = Scores.list_least_compact(:reock)
    assert least_compact.id == ctx.hook.id
    assert most_compact.id == ctx.square.id
    assert unranked.id == ctx.at_large.id
  end

  test "at-large districts keep raw metrics but stay outside the ranking", ctx do
    :ok = Scores.score_current!(:congressional)

    at_large = Scores.get_score(ctx.at_large.id)

    for metric <- [:polsby_popper, :reock, :convex_hull, :schwartzberg] do
      value = Map.fetch!(at_large, metric)
      assert value > 0.0 and value <= 1.0, "at-large #{metric} out of range: #{inspect(value)}"
    end

    assert is_nil(at_large.composite)
    assert is_nil(at_large.national_rank)
    refute Enum.any?(Scores.list_ranked(:congressional), &(&1.id == ctx.at_large.id))

    # It stays in the public field, sorted after every ranked district.
    assert ctx.at_large.id ==
             :composite |> Scores.list_least_compact() |> List.last() |> Map.fetch!(:id)

    assert %{slug: "wy-0"} = Scores.get_current_district("wy-0")
  end

  test "re-ranking clears a stale at-large composite and rank", ctx do
    :ok = Scores.score_current!(:congressional)

    # Simulate scores published before at-large districts were excluded.
    ctx.at_large.id
    |> Scores.get_score()
    |> Ecto.Changeset.change(composite: 0.9, national_rank: 1)
    |> VNI.Repo.update!()

    :ok = Scores.normalize_and_rank!(:congressional)

    at_large = Scores.get_score(ctx.at_large.id)
    assert is_nil(at_large.composite)
    assert is_nil(at_large.national_rank)
  end

  # The mid-decade case the versioning model exists for: NC, LA, GA, and AL
  # all redrew between the 118th and 119th Congresses, so the same seat
  # exists under two map versions in two different normalization cohorts.
  describe "historical congress cohorts" do
    setup do
      closed = %{effective_from: ~D[2023-01-03], effective_until: ~D[2025-01-02]}

      {:ok, nc118} =
        Atlas.create_map_version(
          Map.merge(%{state: "NC", level: :congressional, congress: 118}, closed)
        )

      {:ok, ga118} =
        Atlas.create_map_version(
          Map.merge(%{state: "GA", level: :congressional, congress: 118}, closed)
        )

      {:ok, nc_square} =
        Atlas.upsert_district(nc118, %{state: "NC", number: 1, geom: square_geom()})

      {:ok, nc_hook} = Atlas.upsert_district(nc118, %{state: "NC", number: 2, geom: hook_geom()})

      {:ok, ga_sliver} =
        Atlas.upsert_district(ga118, %{state: "GA", number: 1, geom: sliver_hook_geom()})

      %{nc_square: nc_square, nc_hook: nc_hook, ga_sliver: ga_sliver}
    end

    test "a historical congress normalizes and ranks within its own cohort", ctx do
      :ok = Scores.score_current!(:congressional)
      :ok = Scores.score_congress!(118, :congressional)

      nc_square = Scores.get_score(ctx.nc_square.id)
      nc_hook = Scores.get_score(ctx.nc_hook.id)
      ga_sliver = Scores.get_score(ctx.ga_sliver.id)

      # Ranked 1..3 within the 118th's field only.
      assert nc_square.national_rank == 1
      assert nc_hook.national_rank == 2
      assert ga_sliver.national_rank == 3
      assert nc_square.composite > nc_hook.composite
      assert nc_hook.composite > ga_sliver.composite
      assert nc_square.methodology_version == Scores.methodology_version()

      # The same hook shape sits in both congresses, but its normalized
      # standing differs because the min-max bounds are cohort-local: in
      # the 119th it is the field's worst shape; in the 118th the GA
      # sliver sits below it.
      tx_hook = Scores.get_score(ctx.hook.id)
      assert nc_hook.composite > tx_hook.composite
    end

    test "scoring a historical congress leaves the current cohort untouched", ctx do
      :ok = Scores.score_current!(:congressional)

      before = %{
        square: Scores.get_score(ctx.square.id),
        hook: Scores.get_score(ctx.hook.id)
      }

      :ok = Scores.score_congress!(118, :congressional)

      assert Scores.get_score(ctx.square.id).composite == before.square.composite
      assert Scores.get_score(ctx.hook.id).composite == before.hook.composite
      assert Scores.get_score(ctx.square.id).national_rank == before.square.national_rank

      # The public ranking still covers only current districts.
      assert Scores.ranked_count(:congressional) == 2

      ranked_ids = Enum.map(Scores.list_ranked(:congressional), & &1.id)
      assert ctx.square.id in ranked_ids
      refute ctx.nc_square.id in ranked_ids
    end

    test "at-large districts stay outside a historical cohort too" do
      {:ok, mt117} =
        Atlas.create_map_version(%{
          state: "MT",
          level: :congressional,
          congress: 117,
          effective_from: ~D[2021-01-03],
          effective_until: ~D[2023-01-02]
        })

      {:ok, at_large} =
        Atlas.upsert_district(mt117, %{state: "MT", number: 0, geom: square_geom()})

      {:ok, _} = Atlas.upsert_district(mt117, %{state: "MT", number: 1, geom: hook_geom()})

      :ok = Scores.score_congress!(117, :congressional)

      score = Scores.get_score(at_large.id)
      assert score.polsby_popper > 0.0
      assert is_nil(score.composite)
      assert is_nil(score.national_rank)
    end
  end

  # A far thinner, longer C than hook_geom — worse on every metric, there
  # to stretch the 118th cohort's min-max bounds below the shared hook.
  defp sliver_hook_geom do
    %Geo.MultiPolygon{
      coordinates: [
        [
          [
            {3.0, 0.0},
            {5.0, 0.0},
            {5.0, 0.01},
            {3.01, 0.01},
            {3.01, 1.99},
            {5.0, 1.99},
            {5.0, 2.0},
            {3.0, 2.0},
            {3.0, 0.0}
          ]
        ]
      ],
      srid: 4326
    }
  end

  test "districts under superseded maps are excluded from ranking", ctx do
    {:ok, _} = Atlas.supersede_map_version(ctx.map_version, ~D[2025-12-31])

    :ok = Scores.score_current!(:congressional)

    assert Scores.list_ranked(:congressional) == []
  end
end
