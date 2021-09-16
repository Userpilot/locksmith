defmodule Locksmith do
  @moduledoc """
  > Queue-free/gen_server-free/process-free locking mechanism built for high concurrency.

  This allows for the use of locks in hot-code-paths without being bottlenecked
  by processes message queues.

  ## Usage

  Simply call the `transaction/2,3,4` function with a locking key, and a function
  to apply, the function is guaranteed to be excluded while exclusively locking the given key.

  ## Examples

  Given two functions, one being slower than the other, the ordering isn't guaranteed
  if both are run by separate process, and if they have some side effects, such as
  update cache values, this could be undesirable.

      iex> myself = self()
      iex> first_function = fn ->
      ...>   :timer.sleep(2_000)
      ...>   send myself, :first_function
      ...> end
      iex> second_function = fn ->
      ...>   :timer.sleep(1_000)
      ...>   send myself, :second_function
      ...> end
      iex> spawn first_function
      iex> spawn second_function
      iex> :ok = receive do
      ...>   :first_function -> :error
      ...>   :second_function -> :ok
      ...> end
      iex> :ok = receive do
      ...>   :first_function -> :ok
      ...>   :second_function -> :error
      ...> end

  Using #{__MODULE__} you can ensure they don't run at the same time by locking both under the same key,
  note that ordering isn't guaranteed per-se as the lock is given on a first-come-first-serve bases.

      iex> myself = self()
      iex> first_function = fn ->
      ...>   :timer.sleep(2_000)
      ...>   send myself, :first_function
      ...> end
      iex> second_function = fn ->
      ...>   :timer.sleep(1_000)
      ...>   send myself, :second_function
      ...> end
      iex> spawn fn -> Locksmith.transaction("somekey", first_function) end
      iex> spawn fn -> Locksmith.transaction("somekey", second_function) end
      iex> :ok = receive do
      ...>   :first_function -> :ok
      ...>   :second_function -> :error
      ...> end
      iex> :ok = receive do
      ...>   :first_function -> :error
      ...>   :second_function -> :ok
      ...> end

  > Notice that after using Locksmith the first transaction which acquired the lock first managed to execute
  > even before the second transaction could start, since the second transaction was
  > locked until the key is released.

  ## Implementation

  When starting this module, it'll initiate an `Eternal` process, which will handle creating and maintaining
  a long live ETS table that is not bound by any process and lives across the applications lifecycle.
  This is required since ETS tables are bound by the process that creates them and when the
  process dies the ETS table is deleted unless their an "heir" to the table, Eternal
  handles retaining the table as long as our app lives.

  Internally this module utilizes `:ets.update_counter/4` function, which provides us with an atomic and
  isolated updates to counter in ETS tables. Given any transaction with a lock key, a lock is
  "acquired", this is achieved by calling `:ets.update_counter/4`, defaulting the lock
  key to counter of value `0` if not found and then incrementing it by `1`,
  if the counter after update is equal to `1` then the lock is acquired
  otherwise the lock isn't acquired.

  The increment operation is done with a `threshold` and `set_value` set to `2` forcing the counter
  to never exceed the value `2`. This means each lock counter is set to a three state value,
  `0` lock is free, `1` lock has been acquired, `2` lock was acquired by someone else.

  After the function is applied the lock is "released" by resetting it's value to `0`, this is done by
  increment by `1`, while having `threshold` and `set_value` to `0` each, forcing the counter to reset
  atomically.

  If the acquire operation fails (returns `false`), the current process is blocked via a `receive/1`
  operation, and before running the `receive/1` operation it'll sent itself a delayed message
  using `Process.send/4`, once it receives the message it sent itself, it'll attempt to
  acquire the lock again, this behaviour is done recursively.
  """

  @doc """
  Given a locking key, an anonymous function of arity zero, lock the given key and execute the function,
  then release the key. If the key is already locked then retry to lock the key and run again
  after some delay. This is achieved by blocking the caller process using a `receive/1`
  call coupled with `Process.send_after/4`.
  """
  @spec transaction(any, (() -> any)) :: any
  def transaction(key, fun)
      when is_function(fun),
      do: apply_with_lock(key, [fun, []])

  def transaction(_key, fun), do: argument_error([fun])

  @doc "Alternative to `transaction/2` that takes an anonymous function of any arity and a list of arguments for it."
  @spec transaction(any, (... -> any), list) :: any
  def transaction(key, fun, args)
      when is_function(fun) and is_list(args),
      do: apply_with_lock(key, [fun, args])

  def transaction(_key, fun, args), do: argument_error([fun, args])

  @doc "Alternative to `transaction/2` that takes an MFA instead of an anonymous function."
  @spec transaction(any, module, atom, list) :: any
  def transaction(key, mod, fun, args)
      when is_atom(mod) and is_atom(fun) and is_list(args),
      do: apply_with_lock(key, [mod, fun, args])

  def transaction(_key, mod, fun, args), do: argument_error([mod, fun, args])

  #
  # Internal implementation
  #

  defp apply_with_lock(key, args) do
    if acquire(key) do
      try do: do_apply(args),
          after: release(key)
    else
      Process.send_after(self(), :retry_apply_with_lock, delay())

      receive do
        :retry_apply_with_lock -> apply_with_lock(key, args)
      end
    end
  end

  defp acquire(key) do
    # Atomically increment given key counter by 1, if we go above 2 reset back to 2
    # if no value exists before default to counter value 0.
    #
    # Lock is acquired if we get to be the one to increment the counter to value of 1.
    #
    :ets.update_counter(__MODULE__, key, {2, 1, 2, 2}, {key, 0}) == 1
  rescue
    _reason -> reraise_ets_error(key, "acquire", __STACKTRACE__)
  end

  defp release(key) do
    # Atomically increment given key counter by 1, if we go above 0 reset back to 0
    # if no value exists before default to counter value 0.
    #
    # Effectively here we're forcing the lock counter to go back to zero.
    #
    :ets.update_counter(__MODULE__, key, {2, 1, 0, 0}, {key, 0}) == 0
  rescue
    _reason -> reraise_ets_error(key, "release", __STACKTRACE__)
  end

  defp do_apply([fun])
       when is_function(fun),
       do: fun.()

  defp do_apply([fun, args])
       when is_function(fun) and is_list(args),
       do: apply(fun, args)

  defp do_apply([mod, fun, args])
       when is_atom(mod) and is_atom(fun) and is_list(args),
       do: apply(mod, fun, args)

  # Delay is a random value between 1ms and 50ms
  defp delay, do: :rand.uniform(50) + 1

  #
  # Provide friendly error messages
  #

  # Try to suggest corrections to function calls
  defp argument_error([not_fun])
       when not is_function(not_fun) do
    raise ArgumentError,
      message:
        "cannot apply provided arguments, got " <>
          "#{inspect(not_fun)}.\n" <>
          "  * Did you mean to pass an anonymous function with arity zero?"
  end

  defp argument_error([fun, not_args])
       when is_function(fun) and not is_list(not_args) do
    raise ArgumentError,
      message:
        "cannot apply provided arguments, got " <>
          "#{inspect(fun)} and #{inspect(not_args)}.\n" <>
          "  * Did you mean to pass an anonymous function of arity N? If so maybe you meant to pass " <>
          "#{inspect(fun)} and #{inspect([not_args])} assuming the function passed is of arity 1."
  end

  defp argument_error([mod, fun, not_args])
       when is_atom(mod) and is_atom(fun) and not is_list(not_args) do
    raise ArgumentError,
      message:
        "cannot apply provided arguments, got " <>
          "#{inspect(mod)}, #{inspect(fun)}, and #{inspect(not_args)}.\n" <>
          "  * Did you mean to pass an M:F(A)? If so maybe you meant to pass " <>
          "#{inspect(mod)}, #{inspect(fun)}, and #{inspect([not_args])} " <>
          "assuming the function passed is of arity 1."
  end

  defp argument_error([mod, not_fun, anything])
       when is_atom(mod) and not is_atom(not_fun) do
    raise ArgumentError,
      message:
        "cannot apply provided arguments, got " <>
          "#{inspect(mod)}, #{inspect(not_fun)}, and #{inspect(anything)}.\n" <>
          "  * Did you mean to pass an M:F(A)? If so the second argument must be an atom " <>
          "representing the function to execute in the module.\n" <>
          "    The third argument must also be a list of length equal to the arity of the function."
  end

  defp argument_error(args) do
    raise ArgumentError,
      message:
        "cannot apply provided arguments, got " <>
          (args |> Enum.map(&inspect/1) |> Enum.join(", ")) <>
          ".\n" <>
          "Allowed inputs are either: \n" <>
          "  * Anonymous function of arity zero.\n" <>
          "    * Example: Locksmith.transaction(\"some key\", fn -> IO.inspect(\"some key\") end)\n" <>
          "  * Anonymous function of arity N, and a list of arguments of the same arity.\n" <>
          "    * Example: Locksmith.transaction(\"some key\", fn arg -> IO.inspect(arg) end, [\"some input\"])" <>
          "  * An M:F(A), module/function/arguments.\n" <>
          "    * Example: Locksmith.transaction(\"some key\", Foo, :bar, [\"some input\"])"
  end

  # Let's have a slightly more helpful error message than ETS'
  defp reraise_ets_error(
         key,
         operation,
         [{:ets, :update_counter, _, _} | _stacktrace] = stacktrace
       ) do
    attrs = [
      message:
        "encountered an error while trying to #{operation} the lock for key #{inspect(key)} " <>
          "this probably implies that the backing ETS table is down for some reason " <>
          "please ensure that the Locksmith application is running properly."
    ]

    reraise RuntimeError, attrs, stacktrace
  end
end
