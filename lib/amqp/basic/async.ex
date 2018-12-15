defmodule AMQP.Basic.Async do
  @moduledoc false

  import AMQP.Core
  alias AMQP.Utils
  alias AMQP.Channel

  @doc """
  Publishes a message to an Exchange.

  This method publishes a message to a specific exchange. The message will be routed
  to queues as defined by the exchange configuration and distributed to any subscribers.

  The parameter `exchange` specifies the name of the exchange to publish to. If set to
  empty string, it publishes to the default exchange.
  The `routing_key` parameter specifies the routing key for the message.

  The `payload` parameter specifies the message content as a binary.

  In addition to the previous parameters, the following options can be used:

  # Options

    * `:mandatory` - If set, returns an error if the broker can't route the message to a queue (default `false`);
    * `:immediate` - If set, returns an error if the broker can't deliver te message to a consumer immediately (default `false`);
    * `:content_type` - MIME Content type;
    * `:content_encoding` - MIME Content encoding;
    * `:headers` - Message headers. Can be used with headers Exchanges;
    * `:persistent` - If set, uses persistent delivery mode. Messages marked as `persistent` that are delivered to `durable` \
                      queues will be logged to disk;
    * `:correlation_id` - application correlation identifier;
    * `:priority` - message priority, ranging from 0 to 9;
    * `:reply_to` - name of the reply queue;
    * `:expiration` - how long the message is valid (in milliseconds);
    * `:message_id` - message identifier;
    * `:timestamp` - timestamp associated with this message (epoch time);
    * `:type` - message type as a string;
    * `:user_id` - creating user ID. RabbitMQ will validate this against the active connection user;
    * `:app_id` - publishing application ID.

  ## Examples

      iex> AMQP.Basic.publish chan, \"my_exchange\", \"my_routing_key\", \"Hello World!\", persistent: true
      :ok

  """
  @spec publish(Channel.t(), String.t(), String.t(), String.t(), keyword) ::
          :ok | :blocked | :closing
  def publish(%Channel{pid: pid}, exchange, routing_key, payload, options \\ []) do
    basic_publish =
      basic_publish(
        exchange: exchange,
        routing_key: routing_key,
        mandatory: Keyword.get(options, :mandatory, false),
        immediate: Keyword.get(options, :immediate, false)
      )

    p_basic =
      p_basic(
        content_type: Keyword.get(options, :content_type, :undefined),
        content_encoding: Keyword.get(options, :content_encoding, :undefined),
        headers: Keyword.get(options, :headers, :undefined) |> Utils.to_type_tuple(),
        delivery_mode: if(options[:persistent], do: 2, else: 1),
        priority: Keyword.get(options, :priority, :undefined),
        correlation_id: Keyword.get(options, :correlation_id, :undefined),
        reply_to: Keyword.get(options, :reply_to, :undefined),
        expiration: Keyword.get(options, :expiration, :undefined),
        message_id: Keyword.get(options, :message_id, :undefined),
        timestamp: Keyword.get(options, :timestamp, :undefined),
        type: Keyword.get(options, :type, :undefined),
        user_id: Keyword.get(options, :user_id, :undefined),
        app_id: Keyword.get(options, :app_id, :undefined),
        cluster_id: Keyword.get(options, :cluster_id, :undefined)
      )

    :amqp_channel.cast(pid, basic_publish, amqp_msg(props: p_basic, payload: payload))
  end

  @doc """
  Sets the message prefetch count or prefetech size (in bytes). If `global` is set to `true` this
  applies to the entire Connection, otherwise it applies only to the specified Channel.
  """
  @spec qos(Channel.t(), keyword) :: :ok
  def qos(%Channel{pid: pid}, options \\ []) do
    basic_qos_ok() =
      :amqp_channel.cast(
        pid,
        basic_qos(
          prefetch_size: Keyword.get(options, :prefetch_size, 0),
          prefetch_count: Keyword.get(options, :prefetch_count, 0),
          global: Keyword.get(options, :global, false)
        )
      )

    :ok
  end

  @doc """
  Acknowledges one or more messages. If `multiple` is set to `true`, all messages up to the one
  specified by `delivery_tag` are considered acknowledged by the server.
  """
  @spec ack(Channel.t(), String.t(), keyword) :: :ok | :blocked | :closing
  def ack(%Channel{pid: pid}, delivery_tag, options \\ []) do
    :amqp_channel.cast(
      pid,
      basic_ack(
        delivery_tag: delivery_tag,
        multiple: Keyword.get(options, :multiple, false)
      )
    )
  end

  @doc """
  Rejects (and, optionally, requeues) a message.
  """
  @spec reject(Channel.t(), String.t(), keyword) :: :ok | :blocked | :closing
  def reject(%Channel{pid: pid}, delivery_tag, options \\ []) do
    :amqp_channel.cast(
      pid,
      basic_reject(
        delivery_tag: delivery_tag,
        requeue: Keyword.get(options, :requeue, true)
      )
    )
  end

  @doc """
  Negative acknowledge of one or more messages. If `multiple` is set to `true`, all messages up to the
  one specified by `delivery_tag` are considered as not acknowledged by the server. If `requeue` is set
  to `true`, the message will be returned to the queue and redelivered to the next available consumer.

  This is a RabbitMQ specific extension to AMQP 0.9.1. It is equivalent to reject, but allows rejecting
  multiple messages using the `multiple` option.
  """
  @spec nack(Channel.t(), String.t(), keyword) :: :ok | :blocked | :closing
  def nack(%Channel{pid: pid}, delivery_tag, options \\ []) do
    :amqp_channel.cast(
      pid,
      basic_nack(
        delivery_tag: delivery_tag,
        multiple: Keyword.get(options, :multiple, false),
        requeue: Keyword.get(options, :requeue, true)
      )
    )
  end

  @doc """
  Polls a queue for an existing message.

  Returns the tuple `{:empty, meta}` if the queue is empty or the tuple {:ok, payload, meta} if at least
  one message exists in the queue. The returned meta map includes the entry `message_count` with the
  current number of messages in the queue.

  Receiving messages by polling a queue is not as as efficient as subscribing a consumer to a queue,
  so consideration should be taken when receiving large volumes of messages.

  Setting the `no_ack` option to true will tell the broker that the receiver will not send an acknowledgement of
  the message. Once it believes it has delivered a message, then it is free to assume that the consuming application
  has taken responsibility for it. In general, a lot of applications will not want these semantics, rather, they
  will want to explicitly acknowledge the receipt of a message and have `no_ack` with the default value of false.
  """
  @spec get(Channel.t(), String.t(), keyword) :: {:ok, String.t(), map} | {:empty, map}
  def get(%Channel{pid: pid}, queue, options \\ []) do
    case :amqp_channel.cast(
           pid,
           basic_get(queue: queue, no_ack: Keyword.get(options, :no_ack, false))
         ) do
      {basic_get_ok(
         delivery_tag: delivery_tag,
         redelivered: redelivered,
         exchange: exchange,
         routing_key: routing_key,
         message_count: message_count
       ),
       amqp_msg(
         props:
           p_basic(
             content_type: content_type,
             content_encoding: content_encoding,
             headers: headers,
             delivery_mode: delivery_mode,
             priority: priority,
             correlation_id: correlation_id,
             reply_to: reply_to,
             expiration: expiration,
             message_id: message_id,
             timestamp: timestamp,
             type: type,
             user_id: user_id,
             app_id: app_id,
             cluster_id: cluster_id
           ),
         payload: payload
       )} ->
        {:ok, payload,
         %{
           delivery_tag: delivery_tag,
           redelivered: redelivered,
           exchange: exchange,
           routing_key: routing_key,
           message_count: message_count,
           content_type: content_type,
           content_encoding: content_encoding,
           headers: headers,
           persistent: delivery_mode == 2,
           priority: priority,
           correlation_id: correlation_id,
           reply_to: reply_to,
           expiration: expiration,
           message_id: message_id,
           timestamp: timestamp,
           type: type,
           user_id: user_id,
           app_id: app_id,
           cluster_id: cluster_id
         }}

      basic_get_empty(cluster_id: cluster_id) ->
        {:empty, %{cluster_id: cluster_id}}
    end
  end

  @doc """
  Registers a queue consumer process. The `pid` of the process can be set using
  the `consumer_pid` argument and defaults to the calling process.

  The consumer process will receive the following data structures:

    * `{:basic_deliver, payload, meta}` - This is sent for each message consumed, where \
  `payload` contains the message content and `meta` contains all the metadata set when \
  sending with Basic.publish or additional info set by the broker;
    * `{:basic_consume_ok, %{consumer_tag: consumer_tag}}` - Sent when the consumer \
  process is registered with Basic.consume. The caller receives the same information \
  as the return of Basic.consume;
    * `{:basic_cancel, %{consumer_tag: consumer_tag, no_wait: no_wait}}` - Sent by the \
  broker when the consumer is unexpectedly cancelled (such as after a queue deletion)
    * `{:basic_cancel_ok, %{consumer_tag: consumer_tag}}` - Sent to the consumer process after a call to Basic.cancel

  """
  @spec consume(Channel.t(), String.t(), pid | nil, keyword) :: {:ok, String.t()}
  def consume(%Channel{} = chan, queue, consumer_pid \\ nil, options \\ []) do
    basic_consume =
      basic_consume(
        queue: queue,
        consumer_tag: Keyword.get(options, :consumer_tag, ""),
        no_local: Keyword.get(options, :no_local, false),
        no_ack: Keyword.get(options, :no_ack, false),
        exclusive: Keyword.get(options, :exclusive, false),
        nowait: Keyword.get(options, :no_wait, false),
        arguments: Keyword.get(options, :arguments, [])
      )

    consumer_pid = consumer_pid || self()

    adapter_pid =
      spawn(fn ->
        Process.flag(:trap_exit, true)
        Process.monitor(consumer_pid)
        Process.monitor(chan.pid)
        do_start_consumer(chan, consumer_pid)
      end)

    basic_consume_ok(consumer_tag: consumer_tag) =
      :amqp_channel.subscribe(chan.pid, basic_consume, adapter_pid)

    {:ok, consumer_tag}
  end

  defp do_start_consumer(chan, consumer_pid) do
    receive do
      basic_consume_ok(consumer_tag: consumer_tag) ->
        send(consumer_pid, {:basic_consume_ok, %{consumer_tag: consumer_tag}})
        do_consume(chan, consumer_pid, consumer_tag)
    end
  end

  defp do_consume(chan, consumer_pid, consumer_tag) do
    receive do
      {basic_deliver(
         consumer_tag: consumer_tag,
         delivery_tag: delivery_tag,
         redelivered: redelivered,
         exchange: exchange,
         routing_key: routing_key
       ),
       amqp_msg(
         props:
           p_basic(
             content_type: content_type,
             content_encoding: content_encoding,
             headers: headers,
             delivery_mode: delivery_mode,
             priority: priority,
             correlation_id: correlation_id,
             reply_to: reply_to,
             expiration: expiration,
             message_id: message_id,
             timestamp: timestamp,
             type: type,
             user_id: user_id,
             app_id: app_id,
             cluster_id: cluster_id
           ),
         payload: payload
       )} ->
        send(
          consumer_pid,
          {:basic_deliver, payload,
           %{
             consumer_tag: consumer_tag,
             delivery_tag: delivery_tag,
             redelivered: redelivered,
             exchange: exchange,
             routing_key: routing_key,
             content_type: content_type,
             content_encoding: content_encoding,
             headers: headers,
             persistent: delivery_mode == 2,
             priority: priority,
             correlation_id: correlation_id,
             reply_to: reply_to,
             expiration: expiration,
             message_id: message_id,
             timestamp: timestamp,
             type: type,
             user_id: user_id,
             app_id: app_id,
             cluster_id: cluster_id
           }}
        )

        do_consume(chan, consumer_pid, consumer_tag)

      basic_consume_ok(consumer_tag: consumer_tag) ->
        send(consumer_pid, {:basic_consume_ok, %{consumer_tag: consumer_tag}})
        do_consume(chan, consumer_pid, consumer_tag)

      basic_cancel_ok(consumer_tag: consumer_tag) ->
        send(consumer_pid, {:basic_cancel_ok, %{consumer_tag: consumer_tag}})

      basic_cancel(consumer_tag: consumer_tag, nowait: no_wait) ->
        send(consumer_pid, {:basic_cancel, %{consumer_tag: consumer_tag, no_wait: no_wait}})

      {:DOWN, _ref, :process, ^consumer_pid, reason} ->
        AMQP.Basic.cancel(chan, consumer_tag)
        exit(reason)

      {:DOWN, _ref, :process, _pid, reason} ->
        exit(reason)
    end
  end

  @doc """
  Registers a handler to deal with returned messages. The registered
  process will receive `{:basic_return, payload, meta}` data structures.
  """
  @spec return(Channel.t(), pid) :: :ok
  def return(%Channel{pid: pid}, return_handler_pid) do
    adapter_pid =
      spawn(fn ->
        Process.flag(:trap_exit, true)
        Process.monitor(return_handler_pid)
        Process.monitor(pid)
        handle_return_messages(pid, return_handler_pid)
      end)

    :amqp_channel.register_return_handler(pid, adapter_pid)
  end

  @doc """
  Removes the return handler, if it exists. Does nothing if there is no
  such handler.
  """
  @spec cancel_return(Channel.t()) :: :ok
  def cancel_return(%Channel{pid: pid}) do
    :amqp_channel.unregister_return_handler(pid)
  end

  defp handle_return_messages(chan_pid, return_handler_pid) do
    receive do
      {basic_return(
         reply_code: reply_code,
         reply_text: reply_text,
         exchange: exchange,
         routing_key: routing_key
       ),
       amqp_msg(
         props:
           p_basic(
             content_type: content_type,
             content_encoding: content_encoding,
             headers: headers,
             delivery_mode: delivery_mode,
             priority: priority,
             correlation_id: correlation_id,
             reply_to: reply_to,
             expiration: expiration,
             message_id: message_id,
             timestamp: timestamp,
             type: type,
             user_id: user_id,
             app_id: app_id,
             cluster_id: cluster_id
           ),
         payload: payload
       )} ->
        send(
          return_handler_pid,
          {:basic_return, payload,
           %{
             reply_code: reply_code,
             reply_text: reply_text,
             exchange: exchange,
             routing_key: routing_key,
             content_type: content_type,
             content_encoding: content_encoding,
             headers: headers,
             persistent: delivery_mode == 2,
             priority: priority,
             correlation_id: correlation_id,
             reply_to: reply_to,
             expiration: expiration,
             message_id: message_id,
             timestamp: timestamp,
             type: type,
             user_id: user_id,
             app_id: app_id,
             cluster_id: cluster_id
           }}
        )

        handle_return_messages(chan_pid, return_handler_pid)

      {:DOWN, _ref, :process, _pid, reason} ->
        exit(reason)
    end
  end
end
