defmodule Subscribex.Application do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec

    host = Application.get_env(:subscribex, :rabbit_host)
    connection_name = Application.get_env(:subscribex, :connection_name, Subscribex.Connection)

    children = [worker(Subscribex.Connection, [host, connection_name])]
    opts = [strategy: :one_for_one, name: Subscribex.Supervisor]

    Supervisor.start_link(children, opts)
  end
end

