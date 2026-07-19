defmodule VNIWeb.CongressTimeTest do
  use ExUnit.Case, async: true

  alias VNIWeb.CongressTime

  test "unqualified routes resolve to the current Congress" do
    assert {:ok, 119, false} = CongressTime.resolve(nil)
  end

  test "only supported Congress route values resolve" do
    assert {:ok, 114, true} = CongressTime.resolve("114")
    assert {:ok, 115, true} = CongressTime.resolve("115")
    assert {:ok, 116, true} = CongressTime.resolve("116")
    assert {:ok, 117, true} = CongressTime.resolve("117")
    assert {:ok, 118, true} = CongressTime.resolve("118")
    assert {:ok, 119, true} = CongressTime.resolve("119")
    assert :error = CongressTime.resolve("113")
    assert :error = CongressTime.resolve("not-a-congress")
  end

  test "context exposes fixed neighboring URLs without wrapping the timeline" do
    oldest = CongressTime.context(114, :states)
    assert oldest.previous == nil
    assert oldest.next.path == "/congresses/115/states"

    seam = CongressTime.context(117, :states)
    assert seam.previous.path == "/congresses/116/states"
    assert seam.next.path == "/congresses/118/states"

    middle = CongressTime.context(118, :state, "ma")
    assert middle.previous.path == "/congresses/117/states/ma"
    assert middle.next.path == "/congresses/119/states/ma"

    current = CongressTime.context(119, :district, "ny-12")
    assert current.previous.path == "/congresses/118/districts/ny-12"
    assert current.next == nil
    assert current.current?
  end

  test "page paths preserve the ordinary current-day aliases" do
    assert CongressTime.page_path(:states, 119, nil, false) == "/states"
    assert CongressTime.page_path(:district, 119, "ny-12", false) == "/districts/ny-12"
    assert CongressTime.page_path(:states, 119, nil, true) == "/congresses/119/states"
  end

  test "map continuity follows reported redraws, not the presence of a new Congress" do
    assert CongressTime.map_continuity(116, "MA", false).label ==
             "Same district lines as the 115th Congress"

    assert CongressTime.map_continuity(116, "PA", false).changed?
    refute CongressTime.map_continuity(117, "MA", false).changed?
    assert CongressTime.map_continuity(117, "NC", false).changed?
    assert CongressTime.map_continuity(118, "WY", false).changed?

    assert CongressTime.map_continuity(119, "WY", true).label ==
             "At-large · no district lines drawn"
  end
end
