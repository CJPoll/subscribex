defmodule Subscribex do
  @moduledoc """
  Subscribex is a simple way to interface with RabbitMQ. It's split into 2 main
  components:
    * `Subscribex.Broker` — Brokers are wrappers around the RabbitMQ instance.
      Actions go through the broker to get to the connection.
    * `Subscribex.Subscriber` — Subscribers are long-lived connections to a
      RabbitMQ instance that will handle messages as they are read from the
      queue.

  In the following sections, we will provide an overview of those components and
  how they interact with each other. If you're looking for the bare-minimum information
  on how to utilize `Subscribex`, please check
  the [getting started guide](http://hexdocs.pm/subscribex/getting-started.html).

  If you want another example of `Subscribex` wired up within an application, please check
  the [sample application](https://github.com/dnsbty/subscribex_example).

  ## Brokers
  `Subscribex.Broker` is a wrapper around a RabbitMQ instance. We can define a
  broker as follows:
      defmodule MyApp.Broker do
        use Subscribex.Broker, otp_app: :my_app
      end
  Where the configuration for the Broker must be in your application
  environment, usually defined in your `config/config.exs`:
      config :my_app, MyApp.Broker,
        rabbit_host:
          username: "guest",
          password: "guest",
          host: "localhost",
          port: 5672
  If you prefer, you can use a URL to connect instead:
      config :my_app, MyApp.Broker,
        rabbit_host: "amqp://guest:guest@localhost:5672"

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

  ## Subscribers
  Subscribers allow developers to monitor a queue and handle messages from that
  queue as they are published. Let's see an example:
      defmodule MyApp.Queue1Subscriber do
        use Subscribex.Subscriber

        def start_link(broker) do
          Subscribex.Subscriber.start_link(__MODULE__, broker)
        end

        def init(broker) do
          config = %Config{
            auto_ack: true,
            broker: broker,
            queue: "test-queue",
            prefetch_count: 1000,
            exchange: "test-exchange",
            exchange_type: :topic,
            exchange_opts: [durable: true],
            binding_opts: [routing_key: "routing_key"]
          }

          {:ok, config}
        end

        def handle_payload(payload, _channel, _delivery_tag, _redelivered) do
          Logger.info(inspect(payload))
        end
      end

  As messages are read off the queue, they will be passed into the subscriber's
  `handle_payload/4` function for handling.

  For more in-depth discussion about how to utilize `Subscribex.Subscriber`,
  please check the [utilizing subscribers guide](http://hexdocs.pm/subscribex/utilizing-subscribers.html)
  """
end
