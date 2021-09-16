defmodule Locksmith.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    ets_opts = [read_concurrency: true, write_concurrency: true]
    eternal_opts = [quiet: true]

    children = [
      %{
        id: :eternal_locksmith,
        type: :worker,
        start: {Eternal, :start_link, [Locksmith, ets_opts, eternal_opts]}
      }
    ]

    opts = [strategy: :one_for_one, name: Locksmith.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
