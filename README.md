# Latest Release

```elixir
def deps do
 [{:subscribex, "~> 0.9.1"}]
end
```

# Subscribex

A lightweight wrapper around [pma's Elixir AMQP library](https://github.com/pma/amqp).
Compared to the AMQP library, this package adds:

1. Auto-start a global connection to your RabbitMQ server on app startup
1. Auto-reconnect to your RabbitMQ server (at 30 second intervals)
1. A configurable subscriber abstraction
1. Simplified channel creation, with the ability to automatically link or monitor the channel process.

NOTE: `master` is usually in "beta" status. Make sure you pull an actual release.

## Contributor List

Special thanks to:
- cavneb
- justgage
- vorce
- telnicky
- Cohedrin
- ssnickolay
- dconger

Your contributions are greatly appreciated!

## Installation

1. Add `subscribex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:subscribex, "~> 0.8"}]
end
```

2. Create a broker:

```elixir
defmodule MyApp.Broker do
  use Subscribex.Broker, otp_app: :my_app
end
```

3. Configure your broker's amqp server information:

```elixir
config :my_app, MyApp.Broker,
  rabbit_host: [
    username: "guest",
    password: "guest",
    host: "localhost",
    port: 5672
  ]
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

## Usage

### tl;dr

After creating, configuring, and starting a broker, you can add subscribers:

```elixir
defmodule MyApp.Subscribers.ActivityCreated do
  use Subscribex.Subscriber

  require Logger

  def init do
    config =
      %Config{
        queue: "my_queue",
        exchange: "my_exchange",
        exchange_type: :topic,
        binding_opts: [routing_key: "my_key"]
      }

      {:ok, config}
  end

  def handle_payload(payload, _channel, _delivery_tag, _redelivered) do
    Logger.info(payload)
  end

  # handle_error/4 is an optional callback for handling when an exception is
  # raised in handle_payload/4
  #
	# In this example, we reject the message, telling Rabbit not to retry.
  def handle_error(payload, channel, delivery_tag, error) do
    Logger.error("Raised #{inspect error} handling #{inspect payload}")
		reject(channel, delivery_tag, requeue: false)
  end
end
```

You'll then want to configure your application to start your subscriber with your broker:

```elixir
defmodule MyApp.Application do
  use Application
  import Supervisor.Spec

  def start(_type, _args) do
    children =
      case Mix.env() do
        :test -> []
        _ -> [supervisor(MyApp.Broker, [[MyApp.Subscribers.ActivityCreated]])]
      end

    Supervisor.start_link(children, [strategy: :one_for_one])
  end
end
```

If you would like to start multiple subscriber processes for the same queue you can do that as well:

```elixir
defmodule MyApp.Application do
  use Application
  import Supervisor.Spec

  def start(_type, _args) do
    children =
      case Mix.env() do
        :test -> []
        _ -> [supervisor(MyApp.Broker, [[{3, MyApp.Subscribers.ActivityCreated}]])]
      end

    Supervisor.start_link(children, [strategy: :one_for_one])
  end
end
```

### Configuration

First, configure your broker's amqp server information in the appropriate config.exs file:

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

### Simplest example

Once configured, you can start making subscribers.  `Subscribex.Subscriber` is
a behavior which requires three callbacks:

```elixir
  @type redelivered :: boolean()

  @callback init()
	:: {:ok, %Subscribex.Subscriber.Config{}}
  @callback handle_payload(payload, channel, Subscribex.delivery_tag, redelivered)
  :: ignored
	@callback handle_error(payload, channel, Subscribex.delivery_tag, RuntimeError.t)
	:: ignored
```

The Config struct is defined as:

```elixir
  defmodule Config do
    defstruct [
      queue: nil,
      dead_letter_queue: nil,
      dead_letter_exchange: nil,
      exchange: nil,
      exchange_type: nil,
      dead_letter_exchange_type: nil,
      auto_ack: true,
      prefetch_count: 10,
      queue_opts: [],
      dead_letter_queue_opts: [],
      dead_letter_exchange_opts: [],
      exchange_opts: [],
      binding_opts: [],
      dl_binding_opts: []
    ]
  end
```

Assume a queue called "my_queue" is bound to a "my_exchange" exchange using the
routing key "my_key".

An example of a subscriber that pops items off this queue and simply logs the
payloads using Logger is as follows:

```elixir
defmodule MyApp.Subscribers.ActivityCreated do
  use Subscribex.Subscriber

  require Logger

  def init do
    config =
      %Config{
        queue: "my_queue",
        exchange: "my_exchange",
        exchange_type: :topic,
        binding_opts: [routing_key: "my_key"]
      }

      {:ok, config}
  end

  def handle_payload(payload, _channel, _delivery_tag, _redelivered) do
    Logger.info(payload)
  end

  def handle_error(payload, channel, delivery_tag, error) do
    Logger.error("Raised #{inspect error} handling #{inspect payload}")
		Subscribex.reject(channel, delivery_tag, requeue: false)
  end
end
```

### Publishing and Deserializing

Instead of just logging the payload, let's deserialize it from a JSON string,
transform the result, and publish it to a different queue.

Let's say the payload is of the format:
```json
{
  "email": "abc@gmail.com",
  "username": "abc123"
}
```

Let's say our goal is to send the user a welcome email and publish to the
"my_app.new_user.emailed" routing key a result of the format:

```json
{
  "email": "abc@gmail.com",
  "username": "abc123",
  "welcome_email_delivered": true
}
```

```elixir
defmodule MyApp.Subscribers.ActivityCreated do
  use Subscribex.Subscriber

  preprocess &__MODULE__.deserialize/1

  require Logger

  @exchange "my_exchange"

  def init do
    config =
      %Config{
        queue: "my_queue",
        exchange: "my_exchange",
        exchange_type: :topic,
        binding_opts: [routing_key: "my_key"]
      }

      {:ok, config}
  end

  def deserialize(payload) do
    Poison.decode!(payload)
  end

  def handle_payload(%{"email" => email, "username" => username} = payload, channel, _delivery_tag, _redelivered) do
    :ok = MyApp.Email.send_welcome_email(email, username)

    {:ok, publishing_payload} =
      payload
      |> Map.put_new("welcome_email_delivered", true)
      |> Poison.encode

    routing_key = "my_app.new_user.emailed"

    Subscribex.publish(channel, @exchange, routing_key, publishing_payload)
  end

  def handle_error(payload, channel, delivery_tag, error) do
    Logger.error("Raised #{inspect error} handling #{inspect payload}")
		Subscribex.reject(channel, delivery_tag, requeue: false)
  end
end
```

Using the `preprocess/1` macro, we can setup plug-like pipelines of functions to
execute before arriving at `handle_payload/4`.

### Manual Acking

Let's take the email example and modify it a bit. It still has the same
requirements, but the email sending is handled by another process, and we don't
want to block the subscriber while it's working.

```elixir
defmodule MyApp.Subscribers.UserRegistered do
  use Subscribex.Subscriber

  preprocess &__MODULE__.deserialize/1

  require Logger

  @exchange "my_exchange"

  def init do
    config =
      %Config{
        queue: "my_queue",
        exchange: "my_exchange",
        exchange_type: :topic,
        binding_opts: [routing_key: "my_key"],
        auto_ack: false # Specify that we want to manually ack these jobs
      }

      {:ok, config}
  end

  def deserialize(payload) do
    Poison.decode!(payload)
  end

  def handle_payload(%{"email" => email, "username" => username}, channel, delivery_tag, _redelivered) do
    # hands off the job to another process, which will be responsible form
    # acking. It must ack the job on the same channel used to receive it.
    :ok = MyApp.Email.send_welcome_email(email, username, channel, delivery_tag)
  end

  def handle_error(payload, channel, delivery_tag, error) do
    Logger.error("Raised #{inspect error} handling #{inspect payload}")
		Subscribex.reject(channel, delivery_tag, requeue: false)
  end
end
```

Because we've told the subscriber we intend to manually ack, we need the channel
and delivery_tag for the payload, which is provided by RabbitMQ. Now the process in
charge of sending the email is responsible for acking the message to RabbitMQ
when it's done processing the message.


In this example, we need a channel to publish the message; we can use the
`MyApp.Broker.channel/1` function, which is spec-ed as:

```elixir
  @spec channel(:link | :no_link | :monitor | function | (channel -> term))
  :: %AMQP.Channel{} | {%AMQP.Channel{}, monitor} | :ok
```

It expects you to pass in :link, :no_link, or :monitor. There is no default
value - you must explicitly pass in the appropriate monitoring scheme for your
use case.

We can then use this channel to publish on. When we use
`MyApp.Broker.channel/1`, we _must_ remember to `MyApp.Broker.close/1` the channel
when we're done with it - otherwise, we'll experience a memory leak as channel
processes are created and never stopped.

If the channel is needed long-term, it's best to either link or monitor it, and
handle the case where a connection failure occurs.

In this case, we only need the process for a short duration. This is why
`Subscribex.channel/1` also accepts a function which takes the channel as an
argument. By doing this, we can do either of the following examples:

```elixir
defmodule MyApp.Email do
  # Code for delivering the email here

  def handle_email_sent(channel, delivery_tag) do
    publish_channel = MyApp.Broker.channel(:link)
    MyApp.Broker.publish(publish_channel, ...other args)
    MyApp.Broker.close(publish_channel)

    MyApp.Broker.ack(channel, delivery_tag)
  end
end
```

Now the process of channel creation and closing are managed for us, and we only
have to code what we need to do with the channel.

Note that acking a message on a different channel than what it was
received on is not allowed by RabbitMQ. So in the above example we should not
ack on the publish_channel. Similarly we should not publish on the channel
we receive messages on as it is not recommended.

## Licensing

Copyright (c) 2018 Cody J. Poll

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
