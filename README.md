# Latest Release

```elixir
def deps do
 [{:subscribex, "~> 0.10.0-rc.0"}]
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
- dbeatty
- justgage
- vorce
- telnicky
- Cohedrin
- ssnickolay
- dconger

Your contributions are greatly appreciated!

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
