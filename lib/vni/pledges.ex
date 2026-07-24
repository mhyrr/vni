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
  alias VNI.Repo

  @token_bytes 32

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
  only, grouped by what they committed to.
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
  def committed_count(district_or_id) do
    counts = district_counts(district_or_id)
    counts.yes + counts.conditional
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

    %{
      yes: Map.get(counts, :yes, 0),
      conditional: Map.get(counts, :conditional, 0),
      no: Map.get(counts, :no, 0)
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
