defmodule Subscribex.Connection do
  use GenServer
  require Logger

  defmodule State do
    defstruct [:connection, :monitor, :host, :name]
  end

  def start_link(host, name \\ __MODULE__) do
    GenServer.start_link(__MODULE__, [host, name])
  end

  def init([host, name]) do
    Logger.info("Starting connection to RabbitMQ...")
    {connection, monitor} = setup(host, name)

    state = %State{
      connection: connection,
      monitor: monitor,
      host: host,
      name: name
    }

    Logger.info("Connected to RabbitMQ successfully")

    {:ok, state}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason},
  %State{host: host, name: name, monitor: monitor} = state) do
    Logger.warn("Rabbit connection died. Trying to restart")

    {connection, monitor} = setup(host, name)

    Logger.info("Rabbit connection reestablished.")

    state = %{state | connection: connection, monitor: monitor}

    {:noreply, state}
  end

  defp setup(host, name) do
    Logger.info("Connecting to RabbitMQ")

    {:ok, connection} = connect(host)
    monitor = Process.monitor(connection.pid)
    Process.register(connection.pid, name)

    {connection, monitor}
  end

  defp connect(""), do: raise "You must define the RabbitMQ host in your :subscribex config"
  defp connect(nil), do: raise "You must define the RabbitMQ host in your :subscribex config"

  defp connect(host) do
    case AMQP.Connection.open(host) do
      {:ok, connection} -> {:ok, connection}
      {:error, _} ->
        interval = Application.get_env(:subscribex, :reconnect_interval, :timer.seconds(30))
        Logger.warn("Connecting to RabbitMQ failed. Retrying in #{inspect (interval / 1000)} seconds")

        :timer.sleep(interval)

        connect(host)
    end
  end
end
