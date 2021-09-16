# Locksmith

> Queue-free/gen_server-free/process-free locking mechanism built for high concurrency.

In certain scenarios you may require to have locking on resources in hot code paths, most locking solutions
require some singular process that, under heavy loads, this may cause bottlenecking on that single
process. Locksmith attempts to avoid this by avoiding all forms of processes to avoid
all kinds of bottlenecks in your hot code paths.

This is achieved by use of `ets:update_counter/4` operations, (ab)using it's atomicity and isolation.

## Installation

The package can be installed by adding `locksmith` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:locksmith, "~> 1.0.0"}
  ]
end
```
