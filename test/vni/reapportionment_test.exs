defmodule VNI.ReapportionmentTest do
  use ExUnit.Case, async: true

  alias VNI.Reapportionment

  # Hand-computed Huntington-Hill example. Priority values P/sqrt(n(n+1)):
  #   A (21_000): 14849.2, 8573.2, 6062.2, 4695.7, 3834.1, 3240.4
  #   B (8_000):   5656.9, 3266.0
  #   C (1_000):    707.1
  # 10 seats = 3 automatic + 7 by priority → A 6, B 3, C 1.
  test "apportions by the method of equal proportions" do
    populations = %{"A" => 21_000, "B" => 8_000, "C" => 1_000}

    assert Reapportionment.apportion(populations, 10) == %{"A" => 6, "B" => 3, "C" => 1}
  end

  test "every state gets at least one seat regardless of population" do
    populations = %{"BIG" => 10_000_000, "TINY" => 1}

    assert %{"TINY" => 1} = Reapportionment.apportion(populations, 5)
  end

  test "seats always sum to the total" do
    populations = Map.new(1..50, fn i -> {"S#{i}", :rand.uniform(30_000_000)} end)
    seats = Reapportionment.apportion(populations, 435)

    assert seats |> Map.values() |> Enum.sum() == 435
    assert Enum.all?(Map.values(seats), &(&1 >= 1))
  end

  test "changes/2 reports only deltas" do
    old = %{"TX" => 36, "CA" => 53, "OH" => 16}
    new = %{"TX" => 38, "CA" => 52, "OH" => 16}

    assert Reapportionment.changes(old, new) == %{"TX" => 2, "CA" => -1}
  end
end
