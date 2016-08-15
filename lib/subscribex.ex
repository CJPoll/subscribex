defmodule Subscribex do
  use Application

  @type monitor :: reference

  def start(_type, _args) do
    import Supervisor.Spec

    host = Application.get_env(:subscribex, :rabbit_host)
    connection_name = Application.get_env(:subscribex, :connection_name, Subscribex.Connection)

    children = [worker(Subscribex.Connection, [host, connection_name])]
    opts = [strategy: :one_for_one, name: Subscribex.Supervisor]

    Supervisor.start_link(children, opts)
  end

  def publish(channel, exchange, routing_key, payload) do
    AMQP.Basic.publish(channel, exchange, routing_key, payload)
  end

  @spec channel(:link | :no_link | :monitor)
  :: %AMQP.Channel{} | {%AMQP.Channel{}, monitor}
  def channel(link \\ :no_link) do
    connection_name = Application.get_env(:subscribex, :connection_name, Subscribex.Connection)
    connection_pid = Process.whereis(connection_name)

    if connection_pid do
      connection = %AMQP.Connection{pid: connection_pid}
      {:ok, channel} = AMQP.Channel.open(connection)

      case link do
        :link ->
          Process.link(channel.pid)
          channel
        :no_link -> channel
        :monitor ->
          monitor = Process.monitor(channel.pid)
          {channel, monitor}
      end
    else
      31
      |> :timer.seconds
      |> :timer.sleep

      channel(link)
    end
  end

  def close(%AMQP.Channel{} = channel) do
    AMQP.Channel.close(channel)
  end
end
