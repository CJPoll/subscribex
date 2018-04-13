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

  @type t :: module

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      otp_app = Keyword.fetch!(opts, :otp_app)
      @otp_app otp_app
      @config Application.get_env(otp_app, __MODULE__, [])

      def start_link(opts \\ []) do
        import Supervisor.Spec

        rabbit_host =
          :rabbit_host
          |> config()
          |> sanitize_host()

        connection_name = Application.get_env(:subscribex, :connection_name, __MODULE__.Connection)

        children = [worker(Subscribex.Connection, [rabbit_host, connection_name])]
        opts = [strategy: :one_for_one, name: Subscribex.Supervisor]

        Supervisor.start_link(children, opts)
      end

      defp config, do: @config

      defp config(key) do
        case Keyword.fetch(@config, key) do
          {:ok, value} -> value
          :error ->
            raise ArgumentError, "missing #{inspect key} configuration in " <>
                           "config #{inspect @otp_app}, #{inspect __MODULE__}"
        end
      end

      defp sanitize_host(host) when is_binary(host), do: host

      defp sanitize_host(credentials) when is_list(credentials) do
        username = Keyword.get(credentials, :username)
        password = Keyword.get(credentials, :password)
        host = Keyword.get(credentials, :host)
        port = Keyword.get(credentials, :port)

        sanitize_host(username, password, host, port)
      end

      defp sanitize_host(username, password, host, port) when is_binary(host) do
        sanitize_host(username, password, to_charlist(host), port)
      end

      defp sanitize_host(username, password, host, port) when is_binary(port) do
        sanitize_host(username, password, host, String.to_integer(port))
      end

      defp sanitize_host(username, password, host, port) do
        [username: username,
         password: password,
         host: host,
         port: port]
      end
    end
  end
end
