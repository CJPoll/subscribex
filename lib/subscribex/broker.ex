defmodule Subscribex.Broker do
  @moduledoc """
  Defines a Broker.

  The broker expects the `:otp_app` as an option. The `:otp_app`
  should point to an OTP application that has the broker
  configuration. For example, the broker:

      defmodule MyApp.Broker do
        use Subscribex.Broker, otp_app: :my_app
      end

  Could be configured with:

      config :my_app, MyApp.Broker,
        host: "localhost",
        username: "guest",
        password: "guest",
        port: 5672

  ## URLs

  Brokers by default support URLs. For example, the configuration
  above could be rewritten to:

      config :my_app, MyApp.Broker,
        url: "amqp://guest:guest@localhost:5672"

  ## Including Within Supervision Tree

  Each broker defines a `start_link/0` function that needs to be invoked before
  using the broker. In general, this function is not called directly, but used
  as part of your application supervision tree.

  If your application was generated with a supervisor (by passing `--sup` to
  `mix new`) you will have a `lib/my_app/application.ex` file (or
  `lib/my_app.ex` for Elixir versions `< 1.4.0`) containing the application
  start callback that defines and starts your supervisor. You just need to edit
  the `start/2` function to start the repo as a supervisor on your application's
  supervisor:
      def start(_type, _args) do
        import Supervisor.Spec
        children = [
          supervisor(MyApp.Broker, [])
        ]
        opts = [strategy: :one_for_one, name: MyApp.Supervisor]
        Supervisor.start_link(children, opts)
      end

  """

  require Logger

  @type channel :: %AMQP.Channel{}

  @typedoc false
  @type callback_return :: term

  @typedoc false
  @type callback :: (... -> callback_return)

  @typedoc false
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

      def start_link(opts \\ []) do
        publisher_count = Keyword.get(opts, :publisher_count, 1)
        Subscribex.Broker.start_link(__MODULE__, publisher_count)
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

  @doc false
  def start_link(broker, count \\ 1) do
    connection_name = config(broker, :connection_name) || :"#{broker}.Connection"

    children = [
      %{id: Subscribex.Connection, type: :worker, start: {Subscribex.Connection, :start_link, [rabbit_host(broker), connection_name]}},
      %{id: Subscribex.Publisher, type: :supervisor, start: {Subscribex.Publisher, :start_link, [broker, count]}}
    ]

    opts = [strategy: :one_for_all, name: :"#{broker}.Supervisor"]

    Supervisor.start_link(children, opts)
  end

  @doc false
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

  @doc false
  @spec sanitize_host(String.t() | Keyword.t()) :: Keyword.t()
  def sanitize_host(host) when is_binary(host), do: host

  def sanitize_host(credentials) when is_list(credentials) do
    username = Keyword.get(credentials, :username)
    password = Keyword.get(credentials, :password)
    host = Keyword.get(credentials, :host)
    port = Keyword.get(credentials, :port)

    sanitize_host(username, password, host, port)
  end

  @doc false
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

  @doc false
  def subscriber_spec(subscriber) when is_atom(subscriber) do
    %{
      id: Module.concat(subscriber, Supervisor),
      type: :supervisor,
      start: {Subscribex.Subscriber.Supervisor, [1, subscriber]}
    }
  end

  def subscriber_spec({count, subscriber}) do
    %{
      id: Module.concat(subscriber, Supervisor),
      type: :supervisor,
      start: {Subscribex.Subscriber.Supervisor, [count, subscriber]}
    }
  end

  @doc false
  def apply_link(%AMQP.Channel{} = channel, :no_link), do: channel

  def apply_link(%AMQP.Channel{} = channel, :monitor) do
    monitor = Process.monitor(channel.pid)
    {channel, monitor}
  end

  def apply_link(%AMQP.Channel{} = channel, :link) do
    Process.link(channel.pid)
    channel
  end

  @doc false
  def channel(broker, link) do
    :"#{broker}.Connection"
    |> Process.whereis()
    |> channel(link, broker)
  end

  @doc false
  def channel(broker, callback, args) when is_function(callback) do
    channel = channel(broker, :link)

    result = apply(callback, [channel | args])

    close(broker, channel)

    result
  end

  def channel(_connection_pid = nil, link, module) do
    Logger.warn("Subscriber application for #{module} not started, trying to reconnect...")

    interval = config(module, :reconnect_interval) || :timer.seconds(30)
    :timer.sleep(interval)

    apply(module, :channel, [link])
  end

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

  @doc false
  @spec channel(module, module, atom, [any]) :: any
  def channel(broker, module, function, args)
      when is_atom(module) and is_atom(function) and is_list(args) do
    channel = channel(broker, :link)
    args = [channel | args]
    result = apply(module, function, args)
    close(broker, channel)

    result
  end

  @doc false
  @spec config(module) :: Keyword.t()
  def config(broker), do: Application.get_env(broker.__otp_app__, broker, [])

  @doc false
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

  @doc false
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

  @doc false
  def rabbit_host(broker) do
    broker
    |> config!(:rabbit_host)
    |> sanitize_host()
  end
end
