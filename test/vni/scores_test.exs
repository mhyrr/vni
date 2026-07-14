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

    %{map_version: mv, square: square, hook: hook}
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

    [least_compact, most_compact] = Scores.list_least_compact(:reock)
    assert least_compact.id == ctx.hook.id
    assert most_compact.id == ctx.square.id
  end

  test "districts under superseded maps are excluded from ranking", ctx do
    {:ok, _} = Atlas.supersede_map_version(ctx.map_version, ~D[2025-12-31])

    :ok = Scores.score_current!(:congressional)

    assert Scores.list_ranked(:congressional) == []
  end
end
