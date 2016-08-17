defmodule Subscribex do
  @type monitor     :: reference
  @type channel     :: %AMQP.Channel{}

  @type routing_key :: String.t
  @type exchange    :: String.t
  @type payload     :: String.t

  @spec publish(channel, exchange, routing_key, payload) :: :ok
  def publish(channel, exchange, routing_key, payload) do
    AMQP.Basic.publish(channel, exchange, routing_key, payload)
  end

  @spec channel(:link | :no_link | :monitor)
  :: %AMQP.Channel{} | {%AMQP.Channel{}, monitor}
  def channel(link) do
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

  @spec close(channel) :: :ok | :closing
  def close(%AMQP.Channel{} = channel) do
    AMQP.Channel.close(channel)
  end
end
