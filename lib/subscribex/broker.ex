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

  @type channel         :: %AMQP.Channel{}

  @type callback_return :: term
  @type callback        :: (... -> callback_return)
  @type delivery_tag  :: term

  @type routing_key     :: String.t
  @type exchange        :: String.t
  @type payload         :: String.t

  @type t :: module

  defmodule InvalidPayloadException do
    defexception [:message]
  end

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      require Logger
      import Subscribex.Broker

      @type monitor         :: reference

      @type callback_return :: term
      @type callback        :: (... -> callback_return)

      otp_app = Keyword.fetch!(opts, :otp_app)
      @otp_app otp_app

      defdelegate close(channel), to: AMQP.Channel
      defdelegate publish(channel, exchange, routing_key, payload, options \\ []), to: Subscribex.Broker
      defdelegate ack(channel, delivery_tag), to: AMQP.Basic
      defdelegate reject(channel, delivery_tag, options), to: AMQP.Basic

      @spec start_link(list(module)) :: Supervisor.on_start()
      def start_link(subscribers \\ []) do
        rabbit_host =
          :rabbit_host
          |> config!()
          |> sanitize_host()

        connection_name = config(:connection_name) || __MODULE__.Connection
        supervisor_name = config(:supervisor_name) || __MODULE__.Subscriber.Supervisor

        subscribers = Enum.map(subscribers, &subscriber_spec/1)
        children = [worker(Subscribex.Connection, [rabbit_host, connection_name]) | subscribers]
        opts = [strategy: :one_for_all, name: __MODULE__.Supervisor]

        Supervisor.start_link(children, opts)
      end

      @spec config :: Keyword.t()
      def config, do: Application.get_env(@otp_app, __MODULE__, [])

      @spec config(atom(), any) :: any
      def config(key, default \\ nil) do
        case Keyword.fetch(config(), key) do
          {:ok, value} -> value
          :error -> default
        end
      end

      @spec config!(atom()) :: any
      def config!(key) do
        case Keyword.fetch(config(), key) do
          {:ok, value} -> value
          _ ->
            raise ArgumentError, "missing #{inspect key} configuration in " <>
                           "config #{inspect @otp_app}, #{inspect __MODULE__}"
        end
      end

      @spec channel(:link | :no_link | :monitor | fun())
      :: %AMQP.Channel{} | {%AMQP.Channel{}, monitor} | any
      def channel(link) when is_atom(link) do
        __MODULE__.Connection
        |> Process.whereis
        |> do_channel(link, __MODULE__)
      end

      @spec channel(callback, [term]) :: callback_return
      def channel(callback, args \\ []) when is_function(callback) do
        channel = channel(:link)

        result = apply(callback, [channel | args])

        close(channel)

        result
      end

      @spec channel(module, atom, [any]) :: any
      def channel(module, function, args)
      when is_atom(module)
      and is_atom(function)
      and is_list(args) do
        channel = channel(:link)
        args = [channel | args]
        result = apply(module, function, args)
        close(channel)

        result
      end
    end
  end

  @spec publish(channel, String.t, String.t, binary, keyword) :: :ok | :blocked | :closing
  def publish(channel, exchange, routing_key, payload, options \\ [])

  def publish(channel, exchange, routing_key, payload, options) when is_binary(payload) do
    AMQP.Basic.publish(channel, exchange, routing_key, payload, options)
  end

  def publish(_, _, _, _, _) do
    raise InvalidPayloadException, "Payload must be a binary"
  end

  @spec sanitize_host(String.t | Keyword.t) :: Keyword.t
  def sanitize_host(host) when is_binary(host), do: host

  def sanitize_host(credentials) when is_list(credentials) do
    username = Keyword.get(credentials, :username)
    password = Keyword.get(credentials, :password)
    host = Keyword.get(credentials, :host)
    port = Keyword.get(credentials, :port)

    sanitize_host(username, password, host, port)
  end

  @spec sanitize_host(String.t, String.t, String.t | charlist(), String.t | integer) :: Keyword.t
  def sanitize_host(username, password, host, port) when is_binary(host) do
    sanitize_host(username, password, to_charlist(host), port)
  end

  def sanitize_host(username, password, host, port) when is_binary(port) do
    sanitize_host(username, password, host, String.to_integer(port))
  end

  def sanitize_host(username, password, host, port) do
    [username: username,
     password: password,
     host: host,
     port: port]
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

  def do_channel(nil, link, module) do
    Logger.warn("Subscriber application not started, trying reconnect...")
    IO.inspect(module, label: "doing channel for module")

    interval = apply(module, :config, [:reconnect_interval, :timer.seconds(30)])
    :timer.sleep(interval)

    apply(module, :channel, [link])
  end

  def do_channel(connection_pid, link, module) when is_pid(connection_pid) do
    IO.inspect(module, label: "doing channel for module")
    connection = %AMQP.Connection{pid: connection_pid}

    Logger.debug("Attempting to create channel")
    {:ok, channel} =
      case AMQP.Channel.open(connection) do
        {:ok, channel} ->
          Logger.debug("Channel created")
          {:ok, channel}
        _ -> apply(module, :channel, [link])
      end

    apply_link(channel, link)
  end
end
