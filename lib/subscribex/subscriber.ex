defmodule Subscribex.Subscriber do
  @type body          :: String.t
  @type channel       :: %AMQP.Channel{}
  @type ignored       :: term
  @type payload       :: term

  @callback auto_ack?                        :: boolean
  @callback durable?                         :: boolean
  @callback provide_channel?                 :: boolean

  @callback exchange_type()                  :: Atom.t | String.t
  @callback exchange()                       :: String.t
  @callback queue()                          :: String.t
  @callback routing_key()                    :: String.t
  @callback prefetch_count()                 :: integer

  @callback deserialize(body) :: {:ok, payload} | {:error, term}

  @callback handle_payload(payload)          :: ignored
  @callback handle_payload(payload, channel) :: ignored
  @callback handle_payload(payload, channel, Subscribex.delivery_tag)
  :: {:ok, :ack} | {:ok, :manual}

  use GenServer
  require Logger
  alias Subscribex.Rabbit

  defmodule State do
    defstruct channel: nil,
    module: nil,
    monitor: nil
  end

  @reconnect_interval :timer.seconds(30)

  defdelegate ack(channel, delivery_tag), to: Subscribex
  defdelegate publish(channel, exchange, routing_key, payload), to: Subscribex

  def start_link(callback_module, opts \\ []) do
    GenServer.start_link(__MODULE__, {callback_module}, opts)
  end

  def init({callback_module}) do
    Logger.info( "Starting subscriber for Rabbit")
    {:ok, channel, monitor} = setup(callback_module)

    state = %State{
      channel: channel,
      module: callback_module,
      monitor: monitor}

    Logger.info( "Started subscriber for Rabbit")

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
        try do
          delegate(payload, tag, state)
        rescue
          error ->
            Logger.error(inspect error)
            ack(state.channel, tag)
        end
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
    auto_ack = apply(state.module, :auto_ack?, [])
    provide_channel = apply(state.module, :provide_channel?, [])

    auto_ack
    |> do_delegate(provide_channel, state, payload, tag)
    |> handle_response(tag, state.channel)
  end

  defp do_delegate(true, true, state, payload, _tag) do
    apply(state.module, :handle_payload, [payload, state.channel])
    {:ok, :ack}
  end

  defp do_delegate(true, _, state, payload, _tag) do
    apply(state.module, :handle_payload, [payload])
    {:ok, :ack}
  end

  defp do_delegate(_, _, state, payload, tag) do
    apply state.module, :handle_payload,  [payload, state.channel, tag]
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

    exchange_type =
      callback_module
      |> apply(:exchange_type, [])
      |> exchange_type()

    routing_keys =
      case routing_keys do
        keys when is_list(keys) -> keys
        key -> [key]
      end

    Rabbit.declare_qos(channel, prefetch_count)
    Rabbit.declare_queue(channel, queue, durable: durability)
    Rabbit.declare_exchange(channel, exchange, exchange_type)
    Rabbit.bind_queue(channel, routing_keys, queue, exchange)

    {:ok, _consumer_tag} = AMQP.Basic.consume(channel, queue)

    {:ok, channel, monitor}
  end

  defp exchange_type("topic"), do: :topic
  defp exchange_type("direct"), do: :direct
  defp exchange_type("fanout"), do: :fanout
  defp exchange_type("header"), do: :headers
  defp exchange_type("headers"), do: :headers
  defp exchange_type(type) when is_atom(type), do: type

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
