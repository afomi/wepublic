defmodule Wepublic.Repo do
  use Ecto.Repo,
    otp_app: :wepublic,
    adapter: Ecto.Adapters.Postgres
end
