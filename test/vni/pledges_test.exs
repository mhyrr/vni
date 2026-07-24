defmodule VNI.PledgesTest do
  use VNI.DataCase, async: true

  alias VNI.{Atlas, Pledges, Politics}
  alias VNI.Pledges.Pledge
  alias VNI.Politics.DistrictProfile

  defp district(attrs \\ %{}) do
    state = Map.get(attrs, :state, "TX")
    number = Map.get(attrs, :number, 33)

    {:ok, mv} =
      Atlas.create_map_version(%{
        state: state,
        level: :congressional,
        congress: 119,
        effective_from: ~D[2023-01-03]
      })

    {:ok, district} = Atlas.upsert_district(mv, %{state: state, number: number})

    case Map.get(attrs, :incumbent_party) do
      nil ->
        district

      party ->
        {:ok, _} =
          Politics.upsert_profile(district, %{
            incumbent_name: "Rep. Example",
            incumbent_party: party,
            incumbent_since: 2013
          })

        district
    end
  end

  defp answers(overrides \\ %{}) do
    Map.merge(
      %{
        "email" => "voter@example.com",
        "commitment" => "yes",
        "voted_for_incumbent" => "yes",
        "party" => "democrat"
      },
      overrides
    )
  end

  defp commit!(district, overrides \\ %{}) do
    {:ok, _outcome, _pledge, token} = Pledges.record(district, answers(overrides))
    {:ok, confirmed} = Pledges.confirm(token)
    {confirmed, token}
  end

  describe "recording" do
    test "a new commitment is stored but counts for nothing until confirmed" do
      d = district()

      assert {:ok, :created, %Pledge{} = pledge, token} = Pledges.record(d, answers())
      assert pledge.commitment == :yes
      assert is_nil(pledge.confirmed_at)
      assert Pledges.committed_count(d) == 0

      assert {:ok, confirmed} = Pledges.confirm(token)
      assert confirmed.confirmed_at
      assert Pledges.committed_count(d) == 1
    end

    test "the raw token is never stored — only its digest" do
      d = district()
      {:ok, :created, pledge, token} = Pledges.record(d, answers())

      assert pledge.token_hash == :crypto.hash(:sha256, token)
      refute pledge.token_hash == token
    end

    test "email is normalised so citext uniqueness and the stored value agree" do
      d = district()

      assert {:ok, :created, pledge, _} =
               Pledges.record(d, answers(%{"email" => "  Voter@Example.COM "}))

      assert pledge.email == "voter@example.com"
    end

    test "one commitment per email per district, but the same person may hold seats apart" do
      texas = district(%{state: "TX", number: 33})
      ohio = district(%{state: "OH", number: 9})

      assert {:ok, :created, _, _} = Pledges.record(texas, answers())
      assert {:ok, :created, _, _} = Pledges.record(ohio, answers())

      assert Repo.aggregate(Pledge, :count) == 2
    end

    test "disposable domains are turned away" do
      d = district()

      assert {:error, :disposable_email} =
               Pledges.record(d, answers(%{"email" => "a@mailinator.com"}))

      assert Repo.aggregate(Pledge, :count) == 0
    end

    test "a bad address is a changeset error, not a crash" do
      d = district()
      assert {:error, changeset} = Pledges.record(d, answers(%{"email" => "not-an-address"}))
      assert %{email: ["must be a valid email address"]} = errors_on(changeset)
    end
  end

  describe "re-submission" do
    test "an unconfirmed pledge may be replaced and gets a fresh token" do
      d = district()
      {:ok, :created, first, old_token} = Pledges.record(d, answers())

      assert {:ok, :reissued, second, new_token} =
               Pledges.record(d, answers(%{"commitment" => "conditional"}))

      assert second.id == first.id
      assert second.commitment == :conditional
      refute new_token == old_token
      assert is_nil(Pledges.fetch_by_token(old_token))
    end

    test "a confirmed pledge keeps its answers — knowing the address is not permission" do
      d = district()
      {pledge, _token} = commit!(d)

      assert {:ok, :already_confirmed, unchanged, recovery_token} =
               Pledges.record(d, answers(%{"commitment" => "no", "party" => "republican"}))

      assert unchanged.id == pledge.id
      assert unchanged.commitment == :yes
      assert unchanged.party == :democrat
      assert unchanged.confirmed_at == pledge.confirmed_at

      # The rotated token still reaches the real owner's manage page.
      assert %Pledge{id: id} = Pledges.fetch_by_token(recovery_token)
      assert id == pledge.id
    end

    test "someone who withdrew can rejoin, but must confirm again" do
      d = district()
      {_pledge, token} = commit!(d)
      {:ok, _} = Pledges.withdraw(token)
      assert Pledges.committed_count(d) == 0

      assert {:ok, :reissued, rejoined, new_token} = Pledges.record(d, answers())
      assert is_nil(rejoined.confirmed_at)
      assert is_nil(rejoined.withdrawn_at)
      assert Pledges.committed_count(d) == 0

      {:ok, _} = Pledges.confirm(new_token)
      assert Pledges.committed_count(d) == 1
    end
  end

  describe "token lifecycle" do
    test "confirm and withdraw are idempotent" do
      d = district()
      {:ok, :created, _, token} = Pledges.record(d, answers())

      {:ok, first} = Pledges.confirm(token)
      {:ok, again} = Pledges.confirm(token)
      assert first.confirmed_at == again.confirmed_at

      {:ok, withdrawn} = Pledges.withdraw(token)
      {:ok, still} = Pledges.withdraw(token)
      assert withdrawn.withdrawn_at == still.withdrawn_at
    end

    test "unknown and malformed tokens are not found rather than fatal" do
      assert {:error, :not_found} = Pledges.confirm("nope")
      assert {:error, :not_found} = Pledges.withdraw("nope")
      assert is_nil(Pledges.fetch_by_token(""))
      assert is_nil(Pledges.fetch_by_token(String.duplicate("x", 500)))
    end

    test "withdrawal drops out of the count immediately" do
      d = district()
      {_pledge, token} = commit!(d)
      assert Pledges.committed_count(d) == 1

      {:ok, _} = Pledges.withdraw(token)
      assert Pledges.committed_count(d) == 0
    end
  end

  describe "counts" do
    test "the headline number holds yes and conditional together, and never no" do
      d = district()
      commit!(d, %{"email" => "a@example.com", "commitment" => "yes"})
      commit!(d, %{"email" => "b@example.com", "commitment" => "conditional"})
      commit!(d, %{"email" => "c@example.com", "commitment" => "no"})

      assert Pledges.district_counts(d) == %{yes: 1, conditional: 1, no: 1}
      assert Pledges.committed_count(d) == 2
    end

    test "counts are scoped to the seat, not shared across districts" do
      texas = district(%{state: "TX", number: 33})
      ohio = district(%{state: "OH", number: 9})

      commit!(texas, %{"email" => "a@example.com"})
      commit!(texas, %{"email" => "b@example.com"})
      commit!(ohio, %{"email" => "c@example.com"})

      assert Pledges.committed_count(texas) == 2
      assert Pledges.committed_count(ohio) == 1
      assert Pledges.national_counts() == %{yes: 3, conditional: 0, no: 0}
    end

    test "an empty district reports zero rather than nothing" do
      assert Pledges.district_counts(district()) == %{yes: 0, conditional: 0, no: 0}
      assert Pledges.national_counts() == %{yes: 0, conditional: 0, no: 0}
    end
  end

  describe "the goal" do
    test "is the last election's margin in votes" do
      profile = %DistrictProfile{last_margin_votes: 2_382}
      assert Pledges.goal(profile) == 2_382
    end

    test "a safe seat gets the enormous number rather than a comfortable one" do
      assert Pledges.goal(%DistrictProfile{last_margin_votes: 184_000}) == 184_000
    end

    test "unopposed seats fall back rather than becoming a goal of 1" do
      # MEDSL codes unopposed seats 1-of-1 (FL-20, OK-3) or 0-of-0; both
      # land on a margin of 100.0, which is exactly the unopposed set.
      unopposed = %DistrictProfile{last_margin_pct: 100.0, last_margin_votes: 1}
      no_tally = %DistrictProfile{last_margin_pct: 100.0, last_margin_votes: 0}

      assert Pledges.goal(unopposed) == Pledges.baseline_goal()
      assert Pledges.goal(no_tally) == Pledges.baseline_goal()
    end

    test "unopposed stays distinguishable — the number cannot carry it" do
      # A fully-tallied unopposed seat records the winner's whole total
      # (AL-4: 274,498), which is not a target. Neither that nor the
      # baseline is a vote goal, so the basis travels with the number.
      al4 = %DistrictProfile{last_margin_pct: 100.0, last_margin_votes: 274_498}

      assert Pledges.goal_basis(al4) == :unopposed

      assert Pledges.goal_basis(%DistrictProfile{
               last_margin_pct: 30.0,
               last_margin_votes: 30_000
             }) ==
               :margin

      assert Pledges.goal_basis(%DistrictProfile{last_margin_votes: nil}) == :unknown
      assert Pledges.goal_basis(nil) == :unknown
    end

    test "a genuinely tiny margin is kept — it is the best evidence on the site" do
      # CA-13, 2024: decided by 187 votes. Rounding that up to a tidier
      # number would throw away the most persuasive fact we hold.
      ca13 = %DistrictProfile{last_margin_pct: 0.07, last_margin_votes: 187}
      assert Pledges.goal(ca13) == 187
    end

    test "a seat new to a redraw falls back rather than showing nothing" do
      assert Pledges.goal(%DistrictProfile{last_margin_votes: nil}) == Pledges.baseline_goal()
      assert Pledges.goal(nil) == Pledges.baseline_goal()
    end
  end

  describe "the target ladder" do
    # OH-9 (Kaptur) was decided by 2,382 votes in 2024.
    defp oh9, do: %DistrictProfile{last_margin_pct: 0.9, last_margin_votes: 2_382}

    test "climbs as the count climbs" do
      assert Pledges.target(oh9(), 0) == 100
      assert Pledges.target(oh9(), 99) == 100
      assert Pledges.target(oh9(), 100) == 500
      assert Pledges.target(oh9(), 501) == 2_382
    end

    test "is capped by the margin, never overshooting it" do
      assert Pledges.target(oh9(), 2_000) == 2_382
      assert Pledges.target(oh9(), 99_999) == 2_382
    end

    test "a close seat's first target is the whole margin" do
      # CA-13, decided by 187 votes: no rung sits below that, so the very
      # first ask is the real number.
      ca13 = %DistrictProfile{last_margin_pct: 0.07, last_margin_votes: 187}
      assert Pledges.target(ca13, 0) == 187
    end

    test "a safe seat climbs rungs instead of showing an unreachable bar" do
      # The median contested seat: 89,631 votes. The margin stays the
      # published fact; the target stays something that can be reached.
      safe = %DistrictProfile{last_margin_pct: 30.0, last_margin_votes: 89_631}

      assert Pledges.target(safe, 0) == 100
      assert Pledges.target(safe, 600) == 2_500
      assert Pledges.target(safe, 60_000) == 89_631
      assert Pledges.goal(safe) == 89_631
    end

    test "unopposed and unknown seats climb without a cap" do
      unopposed = %DistrictProfile{last_margin_pct: 100.0, last_margin_votes: 274_498}

      assert Pledges.target(unopposed, 0) == 100
      assert Pledges.target(unopposed, 3_000) == 10_000
      assert Pledges.target(nil, 0) == 100
    end
  end

  describe "cross-party rate" do
    test "measures commitments against one's own party's incumbent" do
      d = district(%{incumbent_party: :dem})

      # Three Democrats committing against a Democrat; one Republican who is not.
      for i <- 1..3, do: commit!(d, %{"email" => "d#{i}@example.com", "party" => "democrat"})
      commit!(d, %{"email" => "r1@example.com", "party" => "republican"})

      assert %{same_party: 3, total: 4, rate: rate} =
               Pledges.cross_party_rate(min_cell: 4, district_id: d.id)

      assert_in_delta rate, 0.75, 0.001
    end

    test "independents and declined answers leave the denominator rather than skew it" do
      d = district(%{incumbent_party: :dem})

      commit!(d, %{"email" => "a@example.com", "party" => "democrat"})
      commit!(d, %{"email" => "b@example.com", "party" => "independent"})
      commit!(d, %{"email" => "c@example.com", "party" => "declined"})

      assert %{total: 1, same_party: 1} = Pledges.cross_party_rate(min_cell: 1, district_id: d.id)
    end

    test "a rate is withheld below the minimum cell size" do
      d = district(%{incumbent_party: :dem})
      commit!(d, %{"email" => "a@example.com", "party" => "democrat"})

      assert is_nil(Pledges.cross_party_rate(district_id: d.id))
      assert is_nil(Pledges.cross_party_rate())
    end

    test "unconfirmed and withdrawn commitments are outside the statistic" do
      d = district(%{incumbent_party: :dem})

      commit!(d, %{"email" => "a@example.com", "party" => "democrat"})
      {:ok, _, _, unconfirmed} = Pledges.record(d, answers(%{"email" => "b@example.com"}))
      {_p, gone} = commit!(d, %{"email" => "c@example.com", "party" => "democrat"})
      {:ok, _} = Pledges.withdraw(gone)

      refute is_nil(Pledges.fetch_by_token(unconfirmed))
      assert %{total: 1} = Pledges.cross_party_rate(min_cell: 1, district_id: d.id)
    end
  end
end
