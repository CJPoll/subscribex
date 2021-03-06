defmodule Subscribex.Subscriber.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(child) when is_atom(child), do: start_link({child, default_worker_count()})
  def start_link({child, count}) when is_atom(child), do: start_link({child, count}, {})

  def start_link(child, args) when is_atom(child) and is_list(args),
    do: start_link({child, default_worker_count()}, args)

  def start_link({child, count}, args) when is_list(args),
    do: Supervisor.start_link(__MODULE__, {child, count, args})

  def init({child, count, args}) when is_binary(count),
    do: init({child, String.to_integer(count), args})

  def init({child, count, args}) when is_integer(count) do
    import Supervisor.Spec

    children =
      Enum.map(0..(count - 1), fn n ->
        worker(child, args, id: :"#{child}_#{n}")
      end)

    supervise(
      children,
      strategy: :one_for_one,
      name: :"#{child}.Supervisor"
    )
  end

  defp default_worker_count do
    System.schedulers()
  end
end
