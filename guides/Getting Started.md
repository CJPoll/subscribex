# Getting Started

This guide is an introduction to `Subscribex`, a lightweight wrapper around [pma's Elixir AMQP library](https://github.com/pma/amqp)

## Installation

1. Add `subscribex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:subscribex, "~> 0.10.0-rc.0"}]
end
```

2. Create a broker:

```elixir
defmodule MyApp.Broker do
  use Subscribex.Broker, otp_app: :my_app
end
```

3. Configure your broker's amqp server information in the appropriate `config.exs` file:

```elixir
config :my_app, MyApp.Broker,
  rabbit_host: [
    username: "guest",
    password: "guest",
    host: "localhost",
    port: 5672]
```

Alternatively, you can use a well-formed [RabbitMQ URI](https://www.rabbitmq.com/uri-spec.html):

```elixir
config :my_app, MyApp.Broker, rabbit_host: "amqp://guest:guest@localhost"
```

4. Ensure your broker is started before your application, but probably not in test:

```elixir
defmodule MyApp.Application do
  use Application

  import Supervisor.Spec

  def start(_type, _args) do
    children =
      case Mix.env() do
        :test -> []
        _ -> [supervisor(MyApp.Broker, [])]
      end

    Supervisor.start_link(children, [strategy: :one_for_one])
  end
end
```

## Simplest Subscriber Example

Once your broker is configured, you can start making subscribers.  `Subscribex.Subscriber` is
a behavior which requires two callbacks:

```elixir
  @type init_args :: term
  @type redelivered :: boolean()
  @type delivery_tag :: term

  @callback init(init_args)
	:: {:ok, %Subscribex.Subscriber.Config{}}
  @callback handle_payload(payload, channel, delivery_tag, redelivered)
  :: ignored
```

The `Subscribex.Subscriber.Config` struct that needs to be returned
from `init/1` is defined as:

```elixir
  defmodule Config do
    defstruct [
      auto_ack: nil,
      binding_opts: [],
      dead_letter_exchange: nil,
      dead_letter_exchange_opts: [],
      dead_letter_exchange_type: nil,
      dead_letter_queue: nil,
      dead_letter_queue_opts: [],
      dl_binding_opts: [],
      exchange: nil,
      exchange_opts: [],
      exchange_type: nil,
      prefetch_count: 10,
      queue: nil,
      queue_opts: [],
      broker: nil
    ]
  end
```

Assume a queue called "my_queue" is bound to a "my_exchange" exchange using the routing key "my_key".

An example of a subscriber that pops items off this queue and simply logs the
payloads using Logger is as follows:

```elixir
defmodule MyApp.Subscribers.SimpleSubscriber do
  use Subscribex.Subscriber

  require Logger

  def init(_init_args) do
    config =
      %Config{
        auto_ack: true,
        broker: MyApp.Broker,
        queue: "my_queue",
        prefetch_count: 10,
        exchange: "my_exchange",
        exchange_type: :topic,
        binding_opts: [routing_key: "my_key"]
      }

      {:ok, config}
  end

  def handle_payload(payload, _channel, _delivery_tag, _redelivered) do
    Logger.info(payload)
  end
end
```
