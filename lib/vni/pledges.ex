defmodule VNI.Pledges do
  @moduledoc """
  Voter commitments about a seat, and the public counts drawn from them.

  The product is the count: "103 people in this district have committed."
  Everything here exists to make that number honest.

  Three rules hold it up:

    * **Double opt-in is absolute.** A row with no `confirmed_at` is
      invisible to every count, aggregate, and statistic published anywhere
      on the site.
    * **Withdrawal is real.** `withdrawn_at` subtracts from the count
      immediately. A number people cannot leave is not worth publishing.
    * **Identities are never public.** Counts and aggregates only, always.
      No surface anywhere exposes who pledged.

  Re-submission semantics are deliberate. An unconfirmed or withdrawn row
  may have its answers replaced — nobody has committed to them yet. A
  *confirmed* row never does: re-submitting an email that already carries a
  confirmed commitment rotates its magic-link token and re-sends the link,
  but leaves the recorded answers untouched. Otherwise knowing someone's
  address would be enough to rewrite what they said.
  """

  import Ecto.Query

  alias VNI.Atlas.District
  alias VNI.Pledges.Pledge
  alias VNI.Politics.DistrictProfile
  alias VNI.Repo

  @token_bytes 32

  # The goal a district's count is measured against, where the margin is
  # missing or too small to mean anything. Published on /methodology with
  # every other rule this site computes.
  @baseline_goal 500

  # Rungs a district climbs while the margin stays out of reach. Capped by
  # the margin itself, so a close seat converges on it rather than stopping
  # at an arbitrary number beneath it.
  @targets [100, 500, 2_500, 10_000, 50_000]

  # design 001 §5: double opt-in, one pledge per email per district, and a
  # disposable-domain blocklist. Deliberately not more — at crawl scale the
  # count being directionally honest is the whole requirement.
  @disposable_domains ~w(
    mailinator.com guerrillamail.com 10minutemail.com yopmail.com
    tempmail.com throwawaymail.com trashmail.com sharklasers.com
    getnada.com dispostable.com fakeinbox.com maildrop.cc
  )

  ## Recording

  @doc """
  Record a commitment and return the raw magic-link token to mail out.

  Returns `{:ok, outcome, pledge, raw_token}` where outcome is one of
  `:created`, `:reissued`, or `:already_confirmed` — the caller decides
  which email that warrants. The raw token exists only in this return
  value; the database stores its SHA-256 and nothing else.
  """
  def record(%District{} = district, attrs) do
    attrs = normalize_attrs(attrs)

    with :ok <- check_domain(attrs["email"]) do
      case existing_pledge(district.id, attrs["email"]) do
        nil -> insert_pledge(district, attrs)
        %Pledge{confirmed_at: nil} = pledge -> replace_answers(pledge, attrs)
        %Pledge{withdrawn_at: %DateTime{}} = pledge -> replace_answers(pledge, attrs)
        %Pledge{} = pledge -> reissue_only(pledge)
      end
    end
  end

  defp insert_pledge(district, attrs) do
    {raw, hash} = new_token()

    %Pledge{district_id: district.id}
    |> Pledge.changeset(attrs)
    |> Ecto.Changeset.put_change(:token_hash, hash)
    |> Repo.insert()
    |> case do
      {:ok, pledge} -> {:ok, :created, pledge, raw}
      {:error, changeset} -> {:error, changeset}
    end
  end

  # Unconfirmed or withdrawn: the answers may be replaced, but re-entering
  # the count requires confirming again from scratch.
  defp replace_answers(%Pledge{} = pledge, attrs) do
    {raw, hash} = new_token()

    pledge
    |> Pledge.changeset(attrs)
    |> Ecto.Changeset.put_change(:token_hash, hash)
    |> Ecto.Changeset.put_change(:confirmed_at, nil)
    |> Ecto.Changeset.put_change(:withdrawn_at, nil)
    |> Repo.update()
    |> case do
      {:ok, pledge} -> {:ok, :reissued, pledge, raw}
      {:error, changeset} -> {:error, changeset}
    end
  end

  # Confirmed: rotate the token so a lost link is recoverable, and touch
  # nothing else. The answers on a confirmed row are not rewritable by
  # anyone who merely knows the address.
  defp reissue_only(%Pledge{} = pledge) do
    {raw, hash} = new_token()

    pledge
    |> Ecto.Changeset.change(token_hash: hash)
    |> Repo.update()
    |> case do
      {:ok, pledge} -> {:ok, :already_confirmed, pledge, raw}
      {:error, changeset} -> {:error, changeset}
    end
  end

  ## Token lifecycle

  @doc """
  Confirm a pledge from its magic-link token. Idempotent: confirming an
  already-confirmed pledge succeeds and leaves `confirmed_at` alone, so a
  reader clicking the link twice sees the same page, not an error.
  """
  def confirm(raw_token) when is_binary(raw_token) do
    case fetch_by_token(raw_token) do
      nil ->
        {:error, :not_found}

      %Pledge{confirmed_at: %DateTime{}} = pledge ->
        {:ok, pledge}

      %Pledge{} = pledge ->
        pledge
        |> Ecto.Changeset.change(confirmed_at: now(), withdrawn_at: nil)
        |> Repo.update()
    end
  end

  @doc "Withdraw a pledge. Idempotent, and drops it from every count at once."
  def withdraw(raw_token) when is_binary(raw_token) do
    case fetch_by_token(raw_token) do
      nil ->
        {:error, :not_found}

      %Pledge{withdrawn_at: %DateTime{}} = pledge ->
        {:ok, pledge}

      %Pledge{} = pledge ->
        pledge
        |> Ecto.Changeset.change(withdrawn_at: now())
        |> Repo.update()
    end
  end

  @doc "Look up a pledge by its raw magic-link token, or nil."
  def fetch_by_token(raw_token) when is_binary(raw_token) do
    case decode_token(raw_token) do
      {:ok, hash} -> Repo.get_by(Pledge, token_hash: hash)
      :error -> nil
    end
  end

  ## Counts

  @doc """
  The published breakdown for one district: confirmed, un-withdrawn rows
  only, grouped by what they committed to, plus the `:committed` headline
  derived from them.

  Breakdown and headline come back together from one query because they
  are published together — the number and its split are the same claim,
  and computing them apart invites them to disagree.
  """
  def district_counts(%District{id: id}), do: district_counts(id)

  def district_counts(district_id) when is_integer(district_id) do
    live()
    |> where([p], p.district_id == ^district_id)
    |> group_by([p], p.commitment)
    |> select([p], {p.commitment, count(p.id)})
    |> Repo.all()
    |> tally()
  end

  @doc """
  The headline number for a district.

  Counts `:yes` and `:conditional` together. The conditional answer — "only
  if others do" — is not a weaker yes; it is the assurance-contract demand
  stated plainly, and the count itself is the "others" it asks about.
  Excluding it would under-report the coalition the number exists to show.
  The breakdown stays available and is published beside it.
  """
  def committed_count(district_or_id), do: district_counts(district_or_id).committed

  ## The goal

  @doc "The fallback goal, and the floor under every computed one."
  def baseline_goal, do: @baseline_goal

  @doc """
  The number a district's count is measured against: the margin, in votes,
  of the seat's last election.

  > Kaptur won this seat by 2,382 votes. That's the goal.

  District-specific, sourced from what we already publish, and it is the
  number that would have decided the last race.

  **What this does not claim.** It is not a model of what flips a seat.
  Flipping means switching votes, and a switched vote moves a margin by
  two; asserting "N commitments take this seat" would be a turnout claim
  we would then have to defend. The margin is a *goal* — legible, sourced,
  district-specific — and the copy says that and nothing more.

  A safe seat therefore shows an enormous goal. That is the argument, not
  a bug: "103 of 184,000" is what "your vote doesn't matter here" looks
  like as a progress bar.

  Falls back to `baseline_goal/0` in exactly two cases: no margin on record
  (a seat new to a redraw), and an unopposed race, which MEDSL codes 0-of-0
  or 1-of-1 and which must not become a goal of 1. `last_margin_pct` of
  100.0 is precisely the unopposed set.

  A small *real* margin is kept as it stands. CA-13 was decided by 187
  votes in 2024, and 187 is the most persuasive number on this site — a
  floor that rounded it up to 500 would be throwing away the best evidence
  we have to make a progress bar look tidier.
  """
  def goal(%DistrictProfile{last_margin_pct: 100.0}), do: @baseline_goal

  def goal(%DistrictProfile{last_margin_votes: votes}) when is_integer(votes) and votes > 0 do
    votes
  end

  def goal(_missing_unscored_or_tied), do: @baseline_goal

  @doc """
  Where a district's goal came from — `:margin`, `:unopposed`, or
  `:unknown`. The number alone cannot carry this, and the difference is
  not cosmetic.

  In an unopposed seat neither available number is a target. The recorded
  margin is the winner's entire vote total (AL-4: 274,498), which is not
  "what it would take to flip" but "what one person got when nobody ran";
  the baseline, meanwhile, would label the most entrenched seats on the
  board as the easiest to move. So the goal there is not really a vote
  count at all — the seat's first missing ingredient is an opponent, and
  the copy should say so. The site never names challengers; noting that
  none existed is a published fact about the seat, not challenger info.
  """
  def goal_basis(%DistrictProfile{last_margin_pct: 100.0}), do: :unopposed

  def goal_basis(%DistrictProfile{last_margin_votes: votes})
      when is_integer(votes) and votes > 0,
      do: :margin

  def goal_basis(_missing_unscored_or_tied), do: :unknown

  @doc """
  The rung a district is currently climbing toward.

  The margin is the right *fact* and the wrong *bar*. Measured against real
  2024 data, the median contested seat was decided by 89,631 votes, and 319
  of 435 districts would render 500 commitments as under one percent — a bar
  that reads as empty in three-quarters of the country is not an indictment
  of safe seats, it is a counter that never appears to move.

  So the two numbers are shown as two numbers: a target that can be reached,
  and the margin stated as what it is.

      103 committed · next target 500
      This seat was decided by 89,631 votes.

  A rung only survives if it is under half the margin, so the ladder never
  stops at a near-miss of the real number. CA-13's margin of 187 admits no
  rung at all, making its very first target the whole 187 — which is the
  point of that district. Unopposed seats have no meaningful cap and simply
  climb.
  """
  def target(profile, count) when is_integer(count) and count >= 0 do
    ladder =
      case goal_basis(profile) do
        :margin ->
          goal = goal(profile)
          Enum.filter(@targets, &(&1 * 2 < goal)) ++ [goal]

        _other ->
          @targets
      end

    Enum.find(ladder, List.last(ladder), &(&1 > count))
  end

  @doc "The same breakdown, nationally."
  def national_counts do
    live()
    |> group_by([p], p.commitment)
    |> select([p], {p.commitment, count(p.id)})
    |> Repo.all()
    |> tally()
  end

  @doc """
  The share of committed people who are agreeing to vote out an incumbent
  of their own party — the project's own falsifiable check on itself.

  Denominator is committed pledges whose party answer maps to a major
  party *and* whose district has a known major-party incumbent; independent,
  other, and declined answers have no same-party reading and are excluded
  rather than counted as a no. Returns `nil` below `min_cell` so a rate can
  never characterise a handful of people.
  """
  def cross_party_rate(opts \\ []) do
    min_cell = Keyword.get(opts, :min_cell, 25)
    district_id = Keyword.get(opts, :district_id)

    query =
      live()
      |> where([p], p.commitment in [:yes, :conditional])
      |> where([p], p.party in [:republican, :democrat])
      |> join(:inner, [p], d in assoc(p, :district))
      |> join(:inner, [p, d], prof in assoc(d, :profile))
      |> where([p, d, prof], prof.incumbent_party in [:dem, :rep])

    query = if district_id, do: where(query, [p], p.district_id == ^district_id), else: query

    rows =
      query
      |> select([p, d, prof], {p.party, prof.incumbent_party})
      |> Repo.all()

    total = length(rows)

    if total < min_cell do
      nil
    else
      same = Enum.count(rows, fn {party, incumbent} -> same_party?(party, incumbent) end)
      %{same_party: same, total: total, rate: same / total}
    end
  end

  defp same_party?(:republican, :rep), do: true
  defp same_party?(:democrat, :dem), do: true
  defp same_party?(_, _), do: false

  # Every public count starts here. Confirmed, not withdrawn — no exceptions.
  defp live do
    from p in Pledge,
      where: not is_nil(p.confirmed_at) and is_nil(p.withdrawn_at)
  end

  defp tally(rows) do
    counts = Map.new(rows)
    yes = Map.get(counts, :yes, 0)
    conditional = Map.get(counts, :conditional, 0)

    %{
      yes: yes,
      conditional: conditional,
      no: Map.get(counts, :no, 0),
      committed: yes + conditional
    }
  end

  ## Internals

  defp existing_pledge(district_id, email) when is_binary(email) do
    Repo.get_by(Pledge, district_id: district_id, email: email)
  end

  defp existing_pledge(_district_id, _email), do: nil

  defp new_token do
    raw = @token_bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    {raw, :crypto.hash(:sha256, raw)}
  end

  defp decode_token(raw) when byte_size(raw) > 0 and byte_size(raw) < 256 do
    {:ok, :crypto.hash(:sha256, raw)}
  end

  defp decode_token(_raw), do: :error

  defp check_domain(email) when is_binary(email) do
    domain = email |> String.trim() |> String.downcase() |> String.split("@") |> List.last()

    if domain in @disposable_domains, do: {:error, :disposable_email}, else: :ok
  end

  defp check_domain(_email), do: :ok

  # Attrs arrive from a form (string keys) or a test (atom keys). Normalise
  # once so the email lookup and the changeset compare the same value.
  defp normalize_attrs(attrs) do
    attrs
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.update("email", nil, fn
      email when is_binary(email) -> email |> String.trim() |> String.downcase()
      other -> other
    end)
  end

  defp now, do: DateTime.utc_now(:second)
end
