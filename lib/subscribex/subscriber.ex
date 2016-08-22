defmodule Subscribex.Subscriber do
  @type body          :: String.t
  @type channel       :: %AMQP.Channel{}
  @type delivery_tag  :: term
  @type ignored       :: term
  @type payload       :: term

  @callback auto_ack?                        :: boolean
  @callback durable?                         :: boolean
  @callback provide_channel?                 :: boolean

  @callback exchange()                       :: String.t
  @callback queue()                          :: String.t
  @callback routing_key()                    :: String.t
  @callback prefetch_count()                 :: integer

  @callback deserialize(body) :: {:ok, payload} | {:error, term}

  @callback handle_payload(payload)          :: ignored
  @callback handle_payload(payload, channel) :: ignored
  @callback handle_payload(payload, channel, delivery_tag)
  :: {:ok, :ack} | {:ok, :manual}

  use GenServer
  require Logger

  defmodule State do
    defstruct channel: nil,
    module: nil,
    monitor: nil
  end

  @reconnect_interval :timer.seconds(30)

  def publish(channel, exchange, routing_key, payload) do
    AMQP.Basic.publish(channel, exchange, routing_key, payload)
  end

  def ack(channel, delivery_tag) do
    AMQP.Basic.ack(channel, delivery_tag)
  end

  def start_link(callback_module, opts \\ []) do
    GenServer.start_link(__MODULE__, {callback_module}, opts)
  end

  def init({callback_module}) do
    IO.inspect "Starting subscriber"
    {:ok, channel, monitor} = setup(callback_module)

    state = %State{
      channel: channel,
      module: callback_module,
      monitor: monitor}
    IO.inspect "Started subscriber"

    {:ok, state}
  end

  def handle_info({:basic_consume_ok, %{consumer_tag: _consumer_tag}}, state) do
    {:noreply, state}
  end

  def handle_info({:basic_cancel, %{consumer_tag: _consumer_tag}}, state) do
    {:noreply, state}
  end

  def handle_info({:basic_deliver, body, %{delivery_tag: tag, redelivered: _redelivered}}, state) do
    case apply(state.module, :deserialize, [body]) do
      {:ok, payload} ->
        delegate(payload, tag, state)
      {:error, reason} ->
        error_message = "Parsing payload: #{body} failed because: #{inspect reason}"
        Logger.error(error_message)
    end

    {:noreply, state}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason},
  %State{module: callback_module, monitor: monitor} = state) do

    Logger.warn("Rabbit connection died. Trying to restart subscriber")
    {:ok, channel, monitor} = setup(callback_module)
    Logger.info("Rabbit subscriber channel reestablished.")

    state = %{state | channel: channel, monitor: monitor}

    {:noreply, state}
  end

  def handle_info(message, state) do
    Logger.warn("Received unknown message: " <> inspect(message))
    {:noreply, state}
  end

  defp delegate(payload, tag, state) do
    try do
      auto_ack = apply(state.module, :auto_ack?, [])
      provide_channel = apply(state.module, :provide_channel?, [])

      response =
        cond do
          auto_ack and provide_channel ->
            apply(state.module, :handle_payload, [payload, state.channel])
            {:ok, :ack}
          auto_ack ->
            apply(state.module, :handle_payload, [payload])
            {:ok, :ack}
          true -> 
            apply state.module, :handle_payload,  [payload, state.channel, tag]
        end

      handle_response(response, tag, state.channel)
    rescue
      error ->
        Logger.error(inspect error)
        ack(state.channel, tag)
    end
  end

  defp handle_response({:ok, :ack}, delivery_tag, channel) do
    ack(channel, delivery_tag)
  end

  defp handle_response(_response, _delivery_tag, _channel), do: nil

  defp setup(callback_module) do
    {channel, monitor} = Subscribex.channel(:monitor)

    queue = apply(callback_module, :queue, [])
    durability = apply(callback_module, :durable?, [])
    exchange = apply(callback_module, :exchange, [])
    prefetch_count = apply(callback_module, :prefetch_count, [])
    routing_keys = apply(callback_module, :routing_key, [])

    declare(channel, prefetch_count, queue, durability, exchange, routing_keys)

    {:ok, _consumer_tag} = AMQP.Basic.consume(channel, queue)

    {:ok, channel, monitor}
  end

  defp declare(channel, prefetch_count, queue, durability, exchange, routing_key) when is_binary(routing_key) do
    declare(channel, prefetch_count, queue, durability, exchange, [routing_key])
  end

  defp declare(channel, prefetch_count, queue, durability, exchange, routing_keys) when is_list(routing_keys) do
    AMQP.Basic.qos(channel, prefetch_count: prefetch_count)

    AMQP.Queue.declare(channel, queue, durable: durability)
    AMQP.Exchange.topic(channel, exchange)
    Enum.each(routing_keys, fn(routing_key) ->
      AMQP.Queue.bind(channel, queue, exchange, [routing_key: routing_key])
    end)
  end

  defmacro __using__(_arg) do
    quote do
      @behaviour Subscribex.Subscriber
      use AMQP

      require Subscribex.Subscriber.Macros
      import Subscribex.Subscriber.Macros
      import Subscribex

      def handle_payload(payload), do: raise "undefined callback handle_payload/1"
      def handle_payload(payload, channel), do: raise "undefined callback handle_payload/2"
      def handle_payload(payload, delivery_tag, channel), do: raise "undefined callback handle_payload/3"

      def auto_ack?, do: true
      def deserialize(payload), do: {:ok, payload}
      def durable?, do: false
      def prefetch_count, do: 10
      def provide_channel?, do: false

      defoverridable [auto_ack?: 0]
      defoverridable [deserialize: 1]
      defoverridable [durable?: 0]
      defoverridable [handle_payload: 1]
      defoverridable [handle_payload: 2]
      defoverridable [handle_payload: 3]
      defoverridable [provide_channel?: 0]
      defoverridable [prefetch_count: 0]
    end
  end
end
