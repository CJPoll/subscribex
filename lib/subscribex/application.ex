defmodule Subscribex.Application do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec


    rabbit_host =
      :subscribex
      |> Application.get_env(:rabbit_host)
      |> sanitize_host

    connection_name = Application.get_env(:subscribex, :connection_name, Subscribex.Connection)

    children = [worker(Subscribex.Connection, [rabbit_host, connection_name])]
    opts = [strategy: :one_for_one, name: Subscribex.Supervisor]

    Supervisor.start_link(children, opts)
  end

  def sanitize_host(host) when is_binary(host), do: host

  def sanitize_host(credentials) when is_list(credentials) do
    username = Keyword.get(credentials, :username)
    password = Keyword.get(credentials, :password)
    host = Keyword.get(credentials, :host)
    port = Keyword.get(credentials, :port)

    sanitize_host(username, password, host, port)
  end

  def sanitize_host(username, password, host, port) when is_binary(host) do
    sanitize_host(username, password, to_charlist(host), port)
  end

  def sanitize_host(username, password, host, port) when is_binary(port) do
    sanitize_host(username, password, host, String.to_integer(port))
  end

  def sanitize_host(username, password, host, port) do
    [username: username,
     password: password,
     host: host,
     port: port]
  end
end

