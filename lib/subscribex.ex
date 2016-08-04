defmodule Subscribex do
  @moduledoc """
  Subscribex is an abstraction for creating workers that subscribe to
  a RabbitMQ queue, and perform some kind of work based on those messages.

  Some things to remember:
    1. If your function crashes, the exception will be caught, and Subscribex
       will ack the message to prevent the message from being resent multiple
       times (potentially crashing the application)
    2. If your function does not crash, Subscribex will automatically ack if
       your function returns {:ok, :ack}
    3. If your function does not crash but needs to hand off processing to a
       background job, return {:ok, :manual}, and YOUR APP will be responsible
       for acking the message (using AMQP.Basic.ack/2)
    3. You must define 4 functions in your module:
          1. exchange/0, which returns the name of the exchange your queue is
             bound to
          2. queue/0, which returns the name of the queue you're subscribing to.
          3. routing_key/0, which returns the name of the routing key for your
             queue/exchange combination.
          4. handle_payload/3, which takes a map from the parsed JSON, the
             delivery tag (for use with AMQP.Basic.ack), and the AMQP channel
             your subscriber is using (also for use with AMQP.Basic.ack)
  """

  @type payload :: term
  @type body :: String.t

  @callback marshal(body) :: {:ok, payload} | {:error, term}
  @callback exchange()                    :: String.t
  @callback queue()                       :: String.t
  @callback routing_key()                 :: String.t
  @callback handle_payload(payload) :: term
  @callback handle_payload(payload, delivery_tag, channel)
  :: {:ok, :ack} |
     {:ok, :manual}

  @type delivery_tag :: any
  @type channel :: %AMQP.Channel{}

  use GenServer
  require Logger

  defmodule State do
    defstruct channel: nil,
      connection: nil,
      host: nil,
      module: nil,
      monitor: nil
  end

  @reconnect_interval :timer.seconds(30)

  def start_link(host, callback_module) do
    GenServer.start_link(__MODULE__, [host, callback_module], [])
  end

  def init([host, callback_module]) do
    Logger.debug("Starting subscriber: #{inspect callback_module}")

    {:ok, connection, channel, monitor} = setup(host, callback_module)

    state = %State{channel: channel,
      connection: connection,
      host: host,
      module: callback_module,
      monitor: monitor}

    Logger.debug("Subscribex created")

    {:ok, state}
  end

  def handle_info({:basic_consume_ok, %{consumer_tag: _consumer_tag}}, state) do
    {:noreply, state}
  end

  def handle_info({:basic_cancel, %{consumer_tag: _consumer_tag}}, state) do
    {:noreply, state}
  end

  def handle_info({:basic_deliver, body, %{delivery_tag: tag, redelivered: _redelivered}}, state) do
    Logger.debug("Basic Deliver")

    case apply(state.module, :marshal, [body]) do
      {:ok, payload} ->
        Logger.debug("Successfully decoded basic deliver")
        delegate(payload, tag, state)
      {:error, reason} ->
        error_message = "Parsing payload: #{body} failed because: #{inspect reason}"
        Logger.error(error_message)
    end

    {:noreply, state}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason},
                  %State{monitor: monitor, host: host, module: callback_module} = state) do

    Logger.warn("Rabbit connection died. Trying to restart")
    {:ok, connection, channel, monitor} = setup(host, callback_module)
    Logger.info("Rabbit connection reestablished.")

    state = %{state | connection: connection, channel: channel, monitor: monitor}

    {:noreply, state}
  end

  def handle_info(message, state) do
    Logger.warn("Received unknown message: " <> inspect(message))
    {:noreply, state}
  end

  defp delegate(payload, tag, state) do
    try do
      Logger.debug("Delegating to: #{inspect state.module}, :handle_payload, [#{inspect payload}]")
      response =
        if apply(state.module, :auto_ack?, []) do
          apply(state.module, :handle_payload, [payload])
          {:ok, :ack}
        else
          apply state.module, :handle_payload,  [payload, tag, state.channel]
        end

      Logger.debug("RESPONSE: #{inspect response}")

      handle_response(response, tag, state.channel)
    rescue
      error ->
        Logger.error(inspect error)
        AMQP.Basic.ack(state.channel, tag)
    end
  end

  defp handle_response({:ok, :ack}, delivery_tag, channel) do
    AMQP.Basic.ack(channel, delivery_tag)
  end

  defp handle_response({:ok, :manual}, _delivery_tag, _channel) do
  end

  defp setup(host, callback_module) do
    {:ok, connection} = connect(host)
    {:ok, channel} = AMQP.Channel.open(connection)

    monitor = Process.monitor(connection.pid)

    queue = apply(callback_module, :queue, [])
    exchange = apply(callback_module, :exchange, [])
    routing_key = apply(callback_module, :routing_key, [])

    AMQP.Basic.qos(channel, prefetch_count: 10)

    Logger.debug("Declaring queue: #{queue}")

    AMQP.Queue.declare(channel, queue, durable: true)
    AMQP.Exchange.topic(channel, exchange)
    AMQP.Queue.bind(channel, queue, exchange, [routing_key: routing_key])
    {:ok, _consumer_tag} = AMQP.Basic.consume(channel, queue)

    {:ok, connection, channel, monitor}
  end

  defp connect(host) do
    case AMQP.Connection.open(host) do
      {:ok, connection} -> {:ok, connection}
      {:error, _} ->
        :timer.sleep(@reconnect_interval)
        connect(host)
    end
  end

  defmacro __using__(_arg) do
    quote do
      @behaviour Subscribex
      use AMQP

      require Subscribex
      import Subscribex

      def handle_payload(payload), do: raise "undefined callback handle_payload/1"
      def handle_payload(payload, delivery_tag, channel), do: raise "undefined callback handle_payload/3"

      def deserialize(body), do: Poison.decode(body)
      def auto_ack?, do: true

      defoverridable [marshal: 1]
      defoverridable [auto_ack?: 0]
      defoverridable [handle_payload: 1]
      defoverridable [handle_payload: 3]
    end
  end

  defmacro routing_key(routing_key) do
    quote do
      def routing_key, do: unquote(routing_key)
    end
  end

  defmacro queue(queue_name) do
    quote do
      def queue, do: unquote(queue_name)
    end
  end

  defmacro exchange(exchange_name) do
    quote do
      def exchange, do: unquote(exchange_name)
    end
  end

  defmacro manual_ack! do
    quote do
      def auto_ack?, do: false
    end
  end
end
