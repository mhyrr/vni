defmodule VNI.Repo.Migrations.CreatePledges do
  use Ecto.Migration

  def change do
    create table(:pledges) do
      add :district_id, references(:districts, on_delete: :restrict), null: false
      add :email, :citext, null: false
      add :commitment, :string, null: false
      add :voted_for_incumbent, :string
      add :party, :string
      add :keep_vote_answer, :text
      add :token_hash, :binary, null: false
      add :confirmed_at, :utc_datetime
      add :withdrawn_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # One commitment per person per seat (design 001 §5 fraud posture).
    create unique_index(:pledges, [:email, :district_id])
    create unique_index(:pledges, [:token_hash])

    # Every public count filters on exactly this shape: confirmed, not
    # withdrawn, for one district. Partial index keeps the counter cheap
    # as the unconfirmed tail grows.
    create index(:pledges, [:district_id],
             where: "confirmed_at IS NOT NULL AND withdrawn_at IS NULL",
             name: :pledges_live_by_district_index
           )
  end
end
