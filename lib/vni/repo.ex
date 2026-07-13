defmodule VNI.Repo do
  use Ecto.Repo,
    otp_app: :vni,
    adapter: Ecto.Adapters.Postgres
end
