defmodule VNI.Atlas.MapAuthorshipTest do
  use VNI.DataCase, async: true

  alias VNI.Atlas
  alias VNI.Atlas.MapAuthorship

  @at_large ~w(AK DE ND SD VT WY)

  test "curates all 50 states, every row cited" do
    rows = MapAuthorship.rows()

    assert length(rows) == 50
    assert Enum.all?(rows, &String.starts_with?(&1.authorship_source_url, "https://"))

    {at_large, districted} = Enum.split_with(rows, &(&1.state in @at_large))

    # At-large states have no lines to draw; everyone else has an
    # authority and a controlling-party call.
    assert length(at_large) == 6
    assert Enum.all?(at_large, &(is_nil(&1.authority) and is_nil(&1.controlling_party)))
    assert Enum.all?(districted, &(&1.authority != nil and &1.controlling_party != nil))
  end

  test "stamps the current map version only, and reruns cleanly" do
    {:ok, superseded} =
      Atlas.create_map_version(%{
        state: "TX",
        level: :congressional,
        congress: 118,
        effective_from: ~D[2023-01-03],
        effective_until: ~D[2025-01-02]
      })

    {:ok, current} =
      Atlas.create_map_version(%{
        state: "TX",
        level: :congressional,
        congress: 119,
        effective_from: ~D[2025-01-03]
      })

    summary = MapAuthorship.seed_current!()

    assert summary.updated == 1
    assert length(summary.missing_states) == 49

    stamped = Atlas.get_map_version!(current.id)
    assert stamped.authority == :legislature
    assert stamped.controlling_party == :rep
    assert stamped.authorship_source_url =~ "redistricting.lls.edu/state/texas"

    # History keeps its own record — a superseded version is never restamped.
    assert Atlas.get_map_version!(superseded.id).authority == nil

    assert %{updated: 1} = MapAuthorship.seed_current!()
  end
end
