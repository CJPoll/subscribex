defmodule Subscribex.Subscriber do
  @moduledoc """
  A Behaviour for consuming from RabbitMQ one message at a time per consumer.
  """

  @type init_args :: term
  @type channel :: %AMQP.Channel{}
  @type redelivered :: boolean
  @type payload :: term
  @type delivery_tag :: term

  @typedoc false
  @type body :: String.t()

  @typedoc false
  @type ignored :: term

  @sync AMQP.Basic
  @async AMQP.Basic.Async

  defmodule InvalidInitValue do
    defexception message: "Invalid value returned from subscriber init function",
                 module: __MODULE__,
                 returned_value: nil
  end

  defmodule Config do
    @moduledoc """
    Specifies the consumer configuration that our subscriber
    will 'declare' when registering.
    """

    @typedoc """
    Exchange type declaration for consumer.

    The default Exchange type is `direct`.

    AMQP 0-9-1 brokers provide four pre-declared exchanges:

      *   Direct exchange: `:direct`
      *   Fanout exchange: `:fanout`
      *   Topic exchange: `:topic`
      *   Headers exchange: `:headers`

    """
    @type exchange_type :: :direct | :fanout | :topic | :headers

    @typedoc """
    Optional configuration parameters for the binding between an exchange
    and a queue.

    The following options can be set:

      * `:prefetch_count`: sets the message prefetch count. This configuration applies only
      to the specified Channel.

    """
    @type binding_opts :: Keyword.t()

    @typedoc """
    Optional configuration parameters for the an exchange.

    The following options can be set on the exchange:

      * `:durable`: If set, keeps the Exchange between restarts of the broker;
      * `:auto_delete`: If set, deletes the Exchange once all queues unbind from it;
      * `:passive`: If set, returns an error if the Exchange does not already exist;
      * `:internal:` If set, the exchange may not be used directly by publishers,
        but only when bound to other exchanges. Internal exchanges are used to construct
        wiring that is not visible to applications.
    """
    @type exchange_opts :: Keyword.t()

    @typedoc """
    Optional configuration parameters for the a queue.

    The following options can be set on the queue:

      * `:durable` - If set, keeps the Queue between restarts of the broker
      * `:auto_delete` - If set, deletes the Queue once all subscribers disconnect
      * `:exclusive` - If set, only one subscriber can consume from the Queue
      * `:passive` - If set, raises an error unless the queue already exists
    """
    @type queue_opts :: Keyword.t()

    @type t :: %__MODULE__{
        auto_ack: boolean | nil,
        binding_opts: binding_opts(),
        dead_letter_exchange: String.t() | nil,
        dead_letter_exchange_opts: Keyword.t(),
        dead_letter_exchange_type: atom() | nil,
        dead_letter_queue: String.t() | nil,
        dead_letter_queue_opts: Keyword.t(),
        dl_binding_opts: Keyword.t(),
        exchange: String.t() | nil,
        exchange_opts: exchange_opts(),
        exchange_type: exchange_type(),
        prefetch_count: integer,
        queue: String.t() | nil,
        queue_opts: queue_opts(),
        broker: nil
      }

    defstruct auto_ack: nil,
              binding_opts: [],
              dead_letter_exchange: nil,
              dead_letter_exchange_opts: [],
              dead_letter_exchange_type: nil,
              dead_letter_queue: nil,
              dead_letter_queue_opts: [],
              dl_binding_opts: [],
              exchange: nil,
              exchange_opts: [],
              exchange_type: nil,
              prefetch_count: 10,
              queue: nil,
              queue_opts: [],
              broker: nil
  end

  defmodule State do
    @moduledoc false
    defstruct [
      :channel,
      :module,
      :monitor,
      :config
    ]
  end

  @callback init(init_args) :: {:ok, %Config{}}
  @callback handle_payload(payload, channel, delivery_tag, redelivered) ::
              {:ok, :ack} | {:ok, :manual}

  use GenServer
  require Logger
  alias Subscribex.Rabbit

  defdelegate ack(channel, delivery_tag), to: @async
  defdelegate reject(channel, delivery_tag, options \\ []), to: @async
  defdelegate publish(channel, exchange, routing_key, payload), to: @async

  @doc false
  def publish_sync(channel, exchange, routing_key, payload) do
    @sync.publish(channel, exchange, routing_key, payload)
  end

  @doc false
  @spec start_link(module) :: GenServer.on_start()
  def start_link(callback_module) do
    GenServer.start_link(__MODULE__, {callback_module, {}})
  end

  @doc false
  @spec start_link(module, init_args) :: GenServer.on_start()
  def start_link(callback_module, init_args) do
    GenServer.start_link(__MODULE__, {callback_module, init_args})
  end

  @doc false
  @spec start_link(module, init_args, GenServer.options()) :: GenServer.on_start()
  def start_link(callback_module, init_args, opts) do
    GenServer.start_link(__MODULE__, {callback_module, init_args}, opts)
  end

  @doc false
  def init({callback_module, init_args}) do
    Logger.debug("Initializing Rabbit Subscriber: #{inspect(callback_module)}")

    config =
      callback_module
      |> apply(:init, [init_args])
      |> validate!(callback_module)

    {:ok, channel, monitor} = setup(config)

    state = %State{
      channel: channel,
      module: callback_module,
      monitor: monitor,
      config: config
    }

    Logger.info("Started subscriber for Rabbit")

    {:ok, state}
  end

  def handle_info({:basic_consume_ok, %{consumer_tag: _consumer_tag}}, state) do
    {:noreply, state}
  end

  def handle_info({:basic_cancel, %{consumer_tag: _consumer_tag}}, state) do
    {:noreply, state}
  end

  def handle_info(
        {:basic_deliver, payload, %{delivery_tag: tag, redelivered: redelivered}},
        state
      ) do
    try do
      payload = apply(state.module, :do_preprocess, [payload])
      apply(state.module, :handle_payload, [payload, state.channel, tag, redelivered])

      if state.config.auto_ack do
        ack(state.channel, tag)
      end
    rescue
      error ->
        Logger.error(
          "#{state.module} threw an error while processing a message: #{inspect(error)}"
        )
    end

    {:noreply, state}
  end

  def handle_info(
        {:DOWN, monitor, :process, _pid, _reason},
        %State{module: callback_module, monitor: monitor} = state
      ) do
    Logger.warn("Rabbit connection died. Trying to restart subscriber")

    {:ok, channel, monitor} =
      callback_module
      |> apply(:init, [])
      |> validate!(callback_module)
      |> setup

    Logger.info("Rabbit subscriber channel reestablished.")

    state = %{state | channel: channel, monitor: monitor}

    {:noreply, state}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  @doc false
  def preprocess(payload, _channel, _delivery_tag, preprocessors) do
    preprocessors = Enum.reverse(preprocessors)

    Enum.reduce(preprocessors, payload, fn preprocessor, payload ->
      preprocessor.(payload)
    end)
  end

  defp setup(%Config{} = config) do
    %{
      broker: broker,
      queue: queue,
      dead_letter_queue: dl_queue,
      dead_letter_exchange: dl_exchange,
      dead_letter_exchange_type: dl_exchange_type,
      dead_letter_exchange_opts: dl_exchange_opts,
      exchange: exchange,
      exchange_type: exchange_type,
      exchange_opts: exchange_opts,
      prefetch_count: prefetch_count,
      binding_opts: binding_opts,
      dl_binding_opts: dl_binding_opts
    } = config

    Logger.info("Creating AMQP Channel for subscriber")
    {channel, monitor} = apply(broker, :channel, [:monitor])

    Rabbit.declare_qos(channel, prefetch_count)
    Rabbit.declare_queue(channel, queue, config.queue_opts)

    unless default_exchange?(exchange) do
      Rabbit.declare_exchange(channel, exchange, exchange_type, exchange_opts)
      Rabbit.bind_queue(channel, queue, exchange, binding_opts)
    end

    if dl_queue do
      Rabbit.declare_queue(channel, dl_queue, config.dead_letter_queue_opts)
      Rabbit.declare_exchange(channel, dl_exchange, dl_exchange_type, dl_exchange_opts)
      Rabbit.bind_queue(channel, dl_queue, dl_exchange, dl_binding_opts)
    end

    {:ok, _consumer_tag} = @sync.consume(channel, queue)

    {:ok, channel, monitor}
  end

  defp validate!(returned_value, callback_module) do
    error_message =
      "Invalid value returned from Subscriber init function (#{inspect(callback_module)})"

    case returned_value do
      {:ok, %Config{auto_ack: nil} = config} ->
        message = """
        Invalid value returned from Subscriber init function (#{inspect(callback_module)}).

        The auto_ack field must be explicitly set in the Config struct when initializing a Subscriber.
        """

        raise_invalid_config(callback_module, message, config)

      {:ok, %Config{broker: nil} = config} ->
        message = """
        Invalid value returned from Subscriber init function (#{inspect(callback_module)}).

        The auto_ack field must be explicitly set in the Config struct when initializing a Subscriber.
        """

        raise_invalid_config(callback_module, message, config)

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

  defp valid?(%Config{auto_ack: nil}), do: false

  defp valid?(%Config{queue: queue, exchange: exchange, exchange_type: type})
       when is_binary(queue) and is_binary(exchange) do
    valid_exchange_type?(type)
  end

  defp valid?(%Config{}), do: false

  defp valid_exchange_type?(:topic), do: true
  defp valid_exchange_type?(:direct), do: true
  defp valid_exchange_type?(:fanout), do: true
  defp valid_exchange_type?(:headers), do: true
  defp valid_exchange_type?(_), do: false

  @doc false
  def raise_invalid_config(module, message, returned_value) do
    IO.inspect("Raising")

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

      require Logger
      alias Subscribex.Subscriber
      import Subscribex.Subscriber
      alias Subscribex.Subscriber.Config

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
        |> Enum.reverse()
        |> Enum.reduce(unquote(payload), fn preprocessor, payload ->
          preprocessor.(payload)
        end)
      end

    {payload, body}
  end

  defp default_exchange?(""), do: true
  defp default_exchange?(_), do: false
end
