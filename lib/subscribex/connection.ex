defmodule Subscribex.Connection do
  use GenServer
  require Logger

  @reconnect_interval :timer.seconds(30)

  defmodule State do
    defstruct [:connection, :monitor, :host, :name]
  end

  def start_link(host, name \\ __MODULE__) do
    GenServer.start_link(__MODULE__, [host, name])
  end

  def init([host, name]) do
    Logger.info("Starting connection to RabitMQ...")
    {connection, monitor} = setup(host, name)

    state = %State{
      connection: connection,
      monitor: monitor,
      host: host,
      name: name
    }

    Logger.info("Connected to RabitMQ successfully")

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
    {:ok, connection} = connect(host)
    monitor = Process.monitor(connection.pid)
    Process.register(connection.pid, name)

    {connection, monitor}
  end

  defp connect(nil) do
    raise "You must define the RabbitMQ host in your :subscribex config"
  end

  defp connect(host) do
    case AMQP.Connection.open(host) do
      {:ok, connection} -> {:ok, connection}
      {:error, _} ->
        :timer.sleep(@reconnect_interval)
        connect(host)
    end
  end
end
