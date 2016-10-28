defmodule Subscribex do
  @type monitor         :: reference
  @type channel         :: %AMQP.Channel{}

  @type callback_return :: term
  @type callback        :: (... -> callback_return)
  @type delivery_tag  :: term

  @type routing_key     :: String.t
  @type exchange        :: String.t
  @type payload         :: String.t

  defdelegate close(channel), to: AMQP.Channel
  defdelegate publish(channel, exchange, routing_key, payload), to: AMQP.Basic
  defdelegate ack(channel, delivery_tag), to: AMQP.Basic

  @spec channel(:link | :no_link | :monitor | fun())
  :: %AMQP.Channel{} | {%AMQP.Channel{}, monitor} | any
  def channel(link) when is_atom(link) do
    :subscribex
    |> Application.get_env(:connection_name, Subscribex.Connection)
    |> Process.whereis
    |> do_channel(link)
  end

  @spec channel(callback, [term]) :: callback_return
  def channel(callback, args \\ []) when is_function(callback) do
    channel = Subscribex.channel(:link)

    result = apply(callback, [channel | args])

    Subscribex.close(channel)

    result
  end

  @spec channel(module, atom, [any]) :: any
  def channel(module, function, args)
  when is_atom(module)
  and is_atom(function)
  and is_list(args) do
    channel = Subscribex.channel(:link)
    args = [channel | args]
    result = apply(module, function, args)
    Subscribex.close(channel)

    result
  end

  ## Private Functions

  defp apply_link(%AMQP.Channel{} = channel, :no_link), do: channel

  defp apply_link(%AMQP.Channel{} = channel, :monitor) do
    monitor = Process.monitor(channel.pid)
    {channel, monitor}
  end

  defp apply_link(%AMQP.Channel{} = channel, :link) do
    Process.link(channel.pid)
    channel
  end

  defp do_channel(nil, link) do
    :subscribex
    |> Application.get_env(:reconnect_interval, :timer.seconds(30))
    |> :timer.sleep

    channel(link)
  end

  defp do_channel(connection_pid, link) when is_pid(connection_pid) do
    connection = %AMQP.Connection{pid: connection_pid}
    {:ok, channel} = AMQP.Channel.open(connection)
    apply_link(channel, link)
  end
end
