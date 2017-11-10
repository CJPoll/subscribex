defmodule Subscribex do
  require Logger

  defmodule InvalidPayloadException do
    defexception [:message]
  end

  @type monitor         :: reference
  @type channel         :: %AMQP.Channel{}

  @type callback_return :: term
  @type callback        :: (... -> callback_return)
  @type delivery_tag  :: term

  @type routing_key     :: String.t
  @type exchange        :: String.t
  @type payload         :: String.t

  defdelegate close(channel), to: AMQP.Channel
  defdelegate ack(channel, delivery_tag), to: AMQP.Basic
  defdelegate reject(channel, delivery_tag, options), to: AMQP.Basic

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

  @spec publish(channel, String.t, String.t, binary, keyword) :: :ok | :blocked | :closing
  def publish(channel, exchange, routing_key, payload, options \\ [])

  def publish(channel, exchange, routing_key, payload, options) when is_binary(payload) do
    AMQP.Basic.publish(channel, exchange, routing_key, payload, options)
  end

  def publish(_, _, _, _, _) do
    raise InvalidPayloadException, "Payload must be a binary"
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
    Logger.warn("Subscriber application not started, trying reconnect...")

    :subscribex
    |> Application.get_env(:reconnect_interval, :timer.seconds(30))
    |> :timer.sleep

    channel(link)
  end

  defp do_channel(connection_pid, link) when is_pid(connection_pid) do
    connection = %AMQP.Connection{pid: connection_pid}

    Logger.debug("Attempting to create channel")
    {:ok, channel} =
      case AMQP.Channel.open(connection) do
        {:ok, channel} ->
          Logger.debug("Channel created")
          {:ok, channel}
        _ -> channel(link)
      end

    apply_link(channel, link)
  end
end
