defmodule VNI.Pledges.Pledge do
  @moduledoc """
  One person's commitment about one seat.

  A pledge is addressed to a district, and districts are map-version-scoped,
  so a pledge is a commitment about *a seat under a particular map*. A
  mid-decade redraw therefore starts the new district's count at zero rather
  than silently carrying a commitment onto lines the person never saw.

  `confirmed_at` is the whole credibility of the published number: nothing
  counts until the double opt-in lands. `withdrawn_at` is the exit, and it
  subtracts from the count the same day it is set — a number people cannot
  leave is not a number worth publishing.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @commitments [:yes, :conditional, :no]
  @votes [:yes, :no, :unsure]
  @parties [:republican, :democrat, :independent, :other, :declined]

  schema "pledges" do
    belongs_to :district, VNI.Atlas.District

    field :email, :string
    field :commitment, Ecto.Enum, values: @commitments
    field :voted_for_incumbent, Ecto.Enum, values: @votes
    field :party, Ecto.Enum, values: @parties
    field :keep_vote_answer, :string

    field :token_hash, :binary
    field :confirmed_at, :utc_datetime
    field :withdrawn_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def commitments, do: @commitments
  def votes, do: @votes
  def parties, do: @parties

  @doc """
  The answers, as submitted. Email is normalised here because the citext
  column makes `Foo@Example.com` and `foo@example.com` the same row, and
  the stored value should match what the uniqueness check compared.
  """
  def changeset(pledge, attrs) do
    pledge
    |> cast(attrs, [
      :email,
      :commitment,
      :voted_for_incumbent,
      :party,
      :keep_vote_answer
    ])
    |> update_change(:email, &normalize_email/1)
    |> validate_required([:email, :commitment])
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@,;]+\.[^\s@,;]+$/,
      message: "must be a valid email address"
    )
    |> validate_length(:email, max: 254)
    |> validate_length(:keep_vote_answer, max: 2000)
    |> foreign_key_constraint(:district_id)
    |> unique_constraint([:email, :district_id],
      message: "has already been recorded for this district"
    )
  end

  defp normalize_email(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase()

  defp normalize_email(other), do: other
end
