defmodule Subscribex.Publisher.Pool do
  @moduledoc false

  use Supervisor

  alias Subscribex.Broker

  @type broker :: module
  @type count :: non_neg_integer
  @opaque pool_name :: {broker, :publisher_pool}
  @type reason :: term
  @type connection_name :: atom

  # Public Functions

  @spec start_link(broker, count, connection_name) :: Supervisor.on_start()
  def start_link(broker, count, connection_name) do
    Supervisor.start_link(__MODULE__, {broker, count, connection_name})
  end

  @spec random_publisher(broker) :: {:ok, Broker.channel()} | {:error, term}
  def random_publisher(broker) do
    result =
      broker
      |> group_name
      |> :pg2.get_closest_pid()

    case result do
      pid when is_pid(pid) -> {:ok, %AMQP.Channel{pid: pid}}
      {:error, _} = err -> err
    end
  end

  @spec add(broker, pid) :: :ok | {:error, reason}
  def add(broker, pid) do
    broker
    |> group_name
    |> :pg2.join(pid)
  end

  # Callback Functions

  def init({broker, count, connection_name}) do
    broker
    |> group_name
    |> :pg2.create()

    children =
      for n <- 1..count do
        worker(
          Subscribex.Publisher.Pool.Worker,
          [broker, connection_name],
          id: :"#{__MODULE__}.Worker.#{n}"
        )
      end

    supervise(children, strategy: :one_for_one)
  end

  # Private Functions

  defp group_name(broker) do
    {broker, :publisher_pool}
  end
end
