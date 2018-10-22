defmodule Subscribex.Subscriber.Supervisor do
  use Supervisor
  import Supervisor.Spec

  def start_link(count, child), do: Supervisor.start_link(__MODULE__, {count, child})

  def init({count, child}) when is_binary(count), do: init({String.to_integer(count), child})

  def init({count, child}) when is_integer(count) do
    children =
      Enum.map(0..(count - 1), fn n ->
        worker(child, [], id: :"#{__MODULE__}_#{n}")
      end)

    supervise(
      children,
      strategy: :one_for_one,
      max_restarts: 100,
      max_seconds: 1,
      name: :"#{child}.Supervisor"
    )
  end

  def init(child) when is_atom(child) do
    children = [worker(child, [], id: :"#{__MODULE__}_0")]

    supervise(
      children,
      strategy: :one_for_one,
      max_restarts: 100,
      max_seconds: 1,
      name: :"#{child}.Supervisor"
    )
  end

  def init(child) do
    IO.inspect(child, label: "Attempting to init supervisor with child")
    child
  end
end
