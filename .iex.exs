alias Subscribex.{TestBroker, TestSubscriber}

defmodule Test do
  alias Subscribex.Rabbit

  @exchange "test-exchange"
  @queue "test-queue"
  @routing_key "routing_key"

  def test do
    TestBroker.channel(fn channel ->
      # this channel is a lightweight connection established by an application that shares a single TCP connection with other applications.
      Rabbit.declare_exchange(channel, @exchange, :topic, durable: true)
      Rabbit.declare_queue(channel, @queue, [])
      Rabbit.bind_queue(channel, @queue, @exchange, routing_key: @routing_key) # establishing a 'binding' (i.e., a rule that tells RabbitMQ how to connect this particular exchange / queue)
    end)

    Enum.each(0..10, fn _ ->
      # TestBroker said use Subscribex.Broker which gave us publish/4
      # Under the hood, publish/4 will find an available worker to publish to your Broker and use that worker's channel
      # to publish to the broker. The default way the worker publishes is asynchronously.
      # To publish in a synchronous (aka blocking fashion) use the publish_sync/4 method instead.
      TestBroker.publish(@exchange, @routing_key, "message")
    end)
  end

  def test_two do
    import Supervisor.Spec

    children = [
      supervisor(TestBroker, [[publisher_count: 1]]),
      worker(TestSubscriber, [TestBroker])
    ]

    Supervisor.start_link(children, [strategy: :one_for_one])
  end
end
# Subscribex.TestBroker.start_link(publisher_count: 1)
