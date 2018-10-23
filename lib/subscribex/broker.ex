defmodule Subscribex.Broker do
  @moduledoc """
  Defines a Broker.

  The broker expects the `:otp_app` as an option. The `:otp_app`
  should point to an OTP application that has the broker
  configuration. For example, the broker:

      defmodule Broker do
        use Subscribex.Broker, otp_app: :my_app
      end

  Could be configured with:

      config :my_app, Broker,
        host: "localhost",
        username: "guest",
        password: "guest",
        port: 5672

  ## URLs

  Brokers by default support URLs. For example, the configuration
  above could be rewritten to:

      config :my_app, Broker,
        url: "amqp://guest:guest@localhost:5672"
  """

  require Logger
  import Supervisor.Spec

  @type channel :: %AMQP.Channel{}

  @type callback_return :: term
  @type callback :: (... -> callback_return)
  @type delivery_tag :: term

  @type routing_key :: String.t()
  @type exchange :: String.t()
  @type payload :: String.t()

  @type t :: module

  defmodule InvalidPayloadException do
    defexception [:message]
  end

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      require Logger
      import Subscribex.Broker

      @type monitor :: reference

      @type callback_return :: term
      @type callback :: (... -> callback_return)

      otp_app = Keyword.fetch!(opts, :otp_app)
      @otp_app otp_app

      @doc false
      def __otp_app__(), do: @otp_app

      def close(channel) do
        Subscribex.Broker.close(__MODULE__, channel)
      end

      def publish(exchange, routing_key, payload, options \\ []) do
        Subscribex.Publisher.publish(__MODULE__, exchange, routing_key, payload, options)
      end

      def publish_sync(exchange, routing_key, payload, options \\ []) do
        Subscribex.Publisher.publish(__MODULE__, exchange, routing_key, payload, options)
      end

      defdelegate ack(channel, delivery_tag), to: AMQP.Basic
      defdelegate reject(channel, delivery_tag, options), to: AMQP.Basic

      def start_link do
        Subscribex.Broker.start_link(__MODULE__)
      end

      @spec channel(:link | :no_link | :monitor | fun()) ::
              %AMQP.Channel{} | {%AMQP.Channel{}, monitor} | any
      def channel(link) when is_atom(link) do
        Subscribex.Broker.channel(__MODULE__, link)
      end

      @spec channel(callback, [term]) :: callback_return
      def channel(callback, args \\ []) when is_function(callback) do
        Subscribex.Broker.channel(__MODULE__, callback, args)
      end

      @spec channel(module, atom, [any]) :: any
      def channel(module, function, args)
          when is_atom(module) and is_atom(function) and is_list(args) do
        Subscribex.Broker.channel(__MODULE__, module, function, args)
      end
    end
  end

  def start_link(broker) do
    connection_name = config(broker, :connection_name) || :"#{broker}.Connection"

    children = [
      worker(Subscribex.Connection, [rabbit_host(broker), connection_name]),
      supervisor(Subscribex.Publisher, [broker])
    ]

    opts = [strategy: :one_for_all, name: :"#{broker}.Supervisor"]

    Supervisor.start_link(children, opts)
  end

  def close(_broker, channel) do
    AMQP.Channel.close(channel)
  end

  @spec publish(channel, String.t(), String.t(), binary, keyword) :: :ok | :blocked | :closing
  def publish(channel, exchange, routing_key, payload, options \\ [])

  def publish(channel, exchange, routing_key, payload, options) when is_binary(payload) do
    AMQP.Basic.Async.publish(channel, exchange, routing_key, payload, options)
  end

  def publish(_, _, _, payload, _) when not is_binary(payload) do
    raise InvalidPayloadException, "Payload must be a binary"
  end

  @spec publish_sync(channel, String.t(), String.t(), binary, keyword) ::
          :ok | :blocked | :closing
  def publish_sync(channel, exchange, routing_key, payload, options \\ [])

  def publish_sync(channel, exchange, routing_key, payload, options) when is_binary(payload) do
    AMQP.Basic.publish(channel, exchange, routing_key, payload, options)
  end

  def publish_sync(_, _, _, payload, _) when not is_binary(payload) do
    raise InvalidPayloadException, "Payload must be a binary"
  end

  @spec sanitize_host(String.t() | Keyword.t()) :: Keyword.t()
  def sanitize_host(host) when is_binary(host), do: host

  def sanitize_host(credentials) when is_list(credentials) do
    username = Keyword.get(credentials, :username)
    password = Keyword.get(credentials, :password)
    host = Keyword.get(credentials, :host)
    port = Keyword.get(credentials, :port)

    sanitize_host(username, password, host, port)
  end

  @spec sanitize_host(String.t(), String.t(), String.t() | charlist(), String.t() | integer) ::
          Keyword.t()
  def sanitize_host(username, password, host, port) when is_binary(host) do
    sanitize_host(username, password, to_charlist(host), port)
  end

  def sanitize_host(username, password, host, port) when is_binary(port) do
    sanitize_host(username, password, host, String.to_integer(port))
  end

  def sanitize_host(username, password, host, port) do
    [username: username, password: password, host: host, port: port]
  end

  def subscriber_spec(subscriber) when is_atom(subscriber) do
    supervisor(
      Subscribex.Subscriber.Supervisor,
      [1, subscriber],
      id: Module.concat(subscriber, Supervisor)
    )
  end

  def subscriber_spec({count, subscriber}) do
    supervisor(
      Subscribex.Subscriber.Supervisor,
      [count, subscriber],
      id: Module.concat(subscriber, Supervisor)
    )
  end

  def apply_link(%AMQP.Channel{} = channel, :no_link), do: channel

  def apply_link(%AMQP.Channel{} = channel, :monitor) do
    monitor = Process.monitor(channel.pid)
    {channel, monitor}
  end

  def apply_link(%AMQP.Channel{} = channel, :link) do
    Process.link(channel.pid)
    channel
  end

  def channel(broker, link) do
    :"#{broker}.Connection"
    |> Process.whereis()
    |> channel(link, broker)
  end

  def channel(broker, callback, args) when is_function(callback) do
    channel = channel(broker, :link)

    result = apply(callback, [channel | args])

    close(broker, channel)

    result
  end

  @doc false
  def channel(_connection_pid = nil, link, module) do
    Logger.warn("Subscriber application for #{module} not started, trying to reconnect...")

    interval = config(module, :reconnect_interval) || :timer.seconds(30)
    :timer.sleep(interval)

    apply(module, :channel, [link])
  end

  @doc false
  def channel(connection_pid, link, module) when is_pid(connection_pid) do
    connection = %AMQP.Connection{pid: connection_pid}

    Logger.debug("Attempting to create channel")

    {:ok, channel} =
      case AMQP.Channel.open(connection) do
        {:ok, channel} ->
          Logger.debug("Channel created")
          {:ok, channel}

        _ ->
          apply(module, :channel, [link])
      end

    apply_link(channel, link)
  end

  @spec channel(module, module, atom, [any]) :: any
  def channel(broker, module, function, args)
      when is_atom(module) and is_atom(function) and is_list(args) do
    channel = channel(broker, :link)
    args = [channel | args]
    result = apply(module, function, args)
    close(broker, channel)

    result
  end

  @spec config(module) :: Keyword.t()
  def config(broker), do: Application.get_env(broker.__otp_app__, broker, [])

  @spec config(module, atom()) :: any
  def config(broker, key) do
    result =
      broker
      |> config
      |> Keyword.fetch(key)

    case result do
      {:ok, value} -> value
      :error -> nil
    end
  end

  @spec config!(module, atom()) :: any
  def config!(broker, key) do
    case Keyword.fetch(config(broker), key) do
      {:ok, value} ->
        value

      _ ->
        raise ArgumentError,
              "missing #{inspect(key)} configuration in " <>
                "config #{inspect(broker.__otp_app__)}, #{inspect(broker)}"
    end
  end

  def rabbit_host(broker) do
    broker
    |> config!(:rabbit_host)
    |> sanitize_host()
  end
end
