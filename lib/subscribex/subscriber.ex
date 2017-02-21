defmodule Subscribex.Subscriber do
  @type body          :: String.t
  @type channel       :: %AMQP.Channel{}
  @type ignored       :: term
  @type payload       :: term

  defmodule InvalidInitValue do
    defexception message: "Invalid value returned from subscriber init function",
      module: __MODULE__,
      returned_value: nil
  end

  defmodule Config do
    defstruct [
      queue: nil,
      dead_letter_queue: nil,
      dead_letter_exchange: nil,
      exchange: nil,
      exchange_type: nil,
      dead_letter_exchange_type: nil,
      auto_ack: true,
      prefetch_count: 10,
      queue_opts: [],
      dead_letter_queue_opts: [],
      dead_letter_exchange_opts: [],
      exchange_opts: [],
      binding_opts: [],
      dl_binding_opts: []
    ]
  end

  defmodule State do
    defstruct [
      :channel,
      :module,
      :monitor,
      :config
    ]
  end

  @callback init() :: {:ok, %Config{}}
  @callback handle_payload(payload, channel, Subscribex.delivery_tag)
  :: {:ok, :ack} | {:ok, :manual}

  use GenServer
  require Logger
  alias Subscribex.Rabbit

  @reconnect_interval :timer.seconds(30)

  defdelegate ack(channel, delivery_tag), to: Subscribex
  defdelegate publish(channel, exchange, routing_key, payload), to: Subscribex

  def start_link(callback_module, opts \\ []) do
    GenServer.start_link(__MODULE__, {callback_module}, opts)
  end

  def init({callback_module}) do
    Logger.info( "Starting subscriber for Rabbit")

    config =
      callback_module
      |> apply(:init, [])
      |> validate!(callback_module)

    {:ok, channel, monitor} = setup(config)

    state = %State{
      channel: channel,
      module: callback_module,
      monitor: monitor,
      config: config}

    Logger.info( "Started subscriber for Rabbit")

    {:ok, state}
  end

  def handle_info({:basic_consume_ok, %{consumer_tag: _consumer_tag}}, state) do
    {:noreply, state}
  end

  def handle_info({:basic_cancel, %{consumer_tag: _consumer_tag}}, state) do
    {:noreply, state}
  end

  def handle_info({:basic_deliver, payload, %{delivery_tag: tag, redelivered: redelivered}}, state) do
    payload = apply(state.module, :do_preprocess, [payload])

    apply(state.module, :handle_payload, [payload, state.channel, tag, redelivered])

    if state.config.auto_ack do
      ack(state.channel, tag)
    end
    {:noreply, state}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason},
  %State{module: callback_module, monitor: monitor} = state) do

    Logger.warn("Rabbit connection died. Trying to restart subscriber")

    {:ok, channel, monitor} = callback_module
                              |> apply(:init, [])
                              |> validate!(callback_module)
                              |> setup

    Logger.info("Rabbit subscriber channel reestablished.")

    state = %{state | channel: channel, monitor: monitor}

    {:noreply, state}
  end

  def handle_info(message, state) do
    Logger.warn("Received unknown message: " <> inspect(message))
    {:noreply, state}
  end

  def preprocess(payload, _channel, _delivery_tag, preprocessors) do
    preprocessors = :lists.reverse(preprocessors)

    Enum.reduce(preprocessors, payload, fn(preprocessor, payload) ->
      preprocessor.(payload)
    end)
  end

  defp setup(%Config{} = config) do
    {channel, monitor} = Subscribex.channel(:monitor)

    queue = config.queue
    dl_queue = config.dead_letter_queue
    dl_exchange = config.dead_letter_exchange
    dl_exchange_type = config.dead_letter_exchange_type
    dl_exchange_opts = config.dead_letter_exchange_opts
    exchange = config.exchange
    exchange_type = config.exchange_type
    exchange_opts = config.exchange_opts
    prefetch_count = config.prefetch_count
    binding_opts = config.binding_opts
    dl_binding_opts = config.dl_binding_opts

    Rabbit.declare_qos(channel, prefetch_count)
    Rabbit.declare_queue(channel, queue, config.queue_opts)

    unless exchange == "" do
      Rabbit.declare_exchange(channel, exchange, exchange_type, exchange_opts)
      Rabbit.bind_queue(channel, queue, exchange, binding_opts)
    end

    if dl_queue do
      Rabbit.declare_queue(channel, dl_queue, config.dead_letter_queue_opts)
      Rabbit.declare_exchange(channel, dl_exchange, dl_exchange_type, dl_exchange_opts)
      Rabbit.bind_queue(channel, dl_queue, dl_exchange, dl_binding_opts)
    end


    {:ok, _consumer_tag} = AMQP.Basic.consume(channel, queue)

    {:ok, channel, monitor}
  end

  defp validate!(returned_value, callback_module) do
  error_message = "Invalid value returned from subscriber init function (#{inspect callback_module})"
    case returned_value do
      {:ok, %Config{} = config} ->
        if valid?(config) do
          config
        else
          raise_invalid_config(callback_module, error_message, config)
        end
      {:ok, return} ->
        raise_invalid_config(callback_module, error_message, return)
      {:error, reason} ->
        raise_invalid_config(callback_module, error_message, reason)
      returned_value ->
        raise_invalid_config(callback_module, error_message, returned_value)
    end
  end

  defp valid?(%Config{queue: queue, exchange: exchange, exchange_type: type})
  when is_binary(queue)
  and is_binary(exchange) do
    valid_exchange_type?(type)
  end

  defp valid?(%Config{}), do: false

  defp valid_exchange_type?(:topic), do: true
  defp valid_exchange_type?(:direct), do: true
  defp valid_exchange_type?(:fanout), do: true
  defp valid_exchange_type?(:headers), do: true
  defp valid_exchange_type?(_), do: false

  def raise_invalid_config(module, message, returned_value) do
    raise InvalidInitValue,
      module: module,
      message: message,
      returned_value: returned_value
  end

  defmacro __using__(_arg) do
    quote do
      @behaviour Subscribex.Subscriber
      Module.register_attribute(__MODULE__, :preprocessors, accumulate: true)
      use AMQP

      require Subscribex.Subscriber.Macros
      import Subscribex.Subscriber.Macros
      import Subscribex
      alias Subscribex.Subscriber.Config

      def handle_payload(payload, delivery_tag, channel), do: raise "undefined callback handle_payload/3"

      def deserialize(payload), do: {:ok, payload}
      def prefetch_count, do: 10
      def provide_channel?, do: false

      defoverridable [deserialize: 1]
      defoverridable [handle_payload: 3]

      @before_compile Subscribex.Subscriber
    end
  end

  defmacro __before_compile__(env) do
    preprocessors = Module.get_attribute(env.module, :preprocessors)

    {payload, body} = Subscribex.Subscriber.compile(preprocessors)

    quote do
      def do_preprocess(unquote(payload)), do: unquote(body)
    end
  end

  @doc false
  def compile(preprocessors) do
    payload = quote do: payload
    body =
      quote do
        unquote(preprocessors)
        |> :lists.reverse
        |> Enum.reduce(unquote(payload), fn(preprocessor, payload) ->
            preprocessor.(payload)
           end)
      end
    {payload, body}
  end
end
