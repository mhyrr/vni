defmodule VNI.Repo.Migrations.AddMarginVotesToDistrictProfiles do
  use Ecto.Migration

  def change do
    # `last_margin_pct` alone cannot answer "how many votes decided this
    # seat" — the commitment goal (design 004 §3) needs the raw counts,
    # which the MEDSL ingest already computes and discarded. Same source,
    # same citation: `margin_source_url` covers all three.
    alter table(:district_profiles) do
      add :last_margin_votes, :integer
      add :last_votes_cast, :integer
    end
  end
end
