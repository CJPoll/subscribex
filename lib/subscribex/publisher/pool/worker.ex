defmodule Subscribex.Publisher.Pool.Worker do
  @moduledoc false

  alias Subscribex.Publisher.Pool
  alias Subscribex.Broker

  def start_link(broker, connection_name) do
    connection = Process.whereis(connection_name)

    %AMQP.Channel{pid: pid} = Broker.channel(connection, :link, broker)

    Pool.add(broker, pid)

    {:ok, pid}
  end
end
