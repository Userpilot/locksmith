defmodule LocksmithTest do
  use ExUnit.Case
  doctest Locksmith

  describe "argument errors" do
    test "Locksmith.transaction/2 fails if passed a non function",
      do: assert_raise(ArgumentError, fn -> Locksmith.transaction("key", "not a function") end)

    test "Locksmith.transaction/3 fails if passed a non function" do
      assert_raise ArgumentError, fn ->
        Locksmith.transaction("key", "not a function", :whatever)
      end
    end

    test "Locksmith.transaction/3 fails if not passed a arguments list" do
      assert_raise ArgumentError, fn ->
        Locksmith.transaction("key", fn a -> a end, :not_a_list)
      end
    end

    test "Locksmith.transaction/4 fails if not passed a arguments list" do
      assert_raise ArgumentError, fn ->
        Locksmith.transaction("key", LocksmithTest.Foo, :bar, :not_a_list)
      end
    end

    test "Locksmith.transaction/4 fails if not passed an atom for function" do
      assert_raise ArgumentError, fn ->
        Locksmith.transaction("key", LocksmithTest.Foo, [:not, :a, :function, :atom], [:whatever])
      end
    end

    test "Locksmith.transaction/3,4 fail if not passed a valid arguments" do
      assert_raise ArgumentError, fn ->
        Locksmith.transaction("key", 10, :anything)
      end

      assert_raise ArgumentError, fn ->
        Locksmith.transaction("key", 10, 20, [:bar])
      end
    end
  end

  describe "Locksmith.transaction/2" do
    test "single function call on some key behaves same as calling apply",
      do: assert(:res = Locksmith.transaction("/2.1", fn -> :res end))

    test "2 function call on same key will have call blocked until key is released" do
      myself = self()

      spawn(fn ->
        Locksmith.transaction("/2.2", fn ->
          Process.sleep(500)

          send(myself, :slow_fun)
        end)
      end)

      # Ensure slow process acquires the lock first
      Process.sleep(50)

      spawn(fn ->
        Locksmith.transaction("/2.2", fn ->
          send(myself, :fast_fun)
        end)
      end)

      assert_receive :slow_fun, 500
      assert_receive :fast_fun
    end

    test "2 function call on different keys will have calls unaffected" do
      myself = self()

      spawn(fn ->
        Locksmith.transaction("/2.3", fn ->
          Process.sleep(500)

          send(myself, :slow_fun)
        end)
      end)

      # Ensure slow process acquires the lock first
      Process.sleep(50)

      spawn(fn ->
        Locksmith.transaction("/2.4", fn ->
          send(myself, :fast_fun)
        end)
      end)

      assert_receive :fast_fun
      assert_receive :slow_fun, 500
    end

    test "N function call on same key will guarantee only one function is call at any given point in time" do
      t = :ets.new(:t, [:public, read_concurrency: true, write_concurrency: true])
      true = :ets.insert(t, {:c, 0})

      tasks =
        for i <- 1..101 do
          Task.async(fn ->
            Locksmith.transaction("/2.5", fn ->
              [c: c] = :ets.lookup(t, :c)

              Process.sleep(101 - i)

              true = :ets.insert(t, {:c, c + i})
            end)
          end)
        end

      Task.await_many(tasks, 10_000)

      assert [c: 5151] = :ets.lookup(t, :c)
    end
  end

  describe "Locksmith.transaction/3" do
    test "single function call on some key behaves same as calling apply",
      do: assert(:res = Locksmith.transaction("/3.1", fn inp -> inp end, [:res]))

    test "2 function call on same key will have call blocked until key is released" do
      myself = self()

      spawn(fn ->
        Locksmith.transaction(
          "/3.2",
          fn arg ->
            Process.sleep(500)

            send(myself, arg)
          end,
          [:slow_fun]
        )
      end)

      # Ensure slow process acquires the lock first
      Process.sleep(50)

      spawn(fn ->
        Locksmith.transaction(
          "/3.2",
          fn arg ->
            send(myself, arg)
          end,
          [:fast_fun]
        )
      end)

      assert_receive :slow_fun, 500
      assert_receive :fast_fun
    end

    test "2 function call on different keys will have calls unaffected" do
      myself = self()

      spawn(fn ->
        Locksmith.transaction(
          "/3.3",
          fn arg ->
            Process.sleep(500)

            send(myself, arg)
          end,
          [:slow_fun]
        )
      end)

      # Ensure slow process acquires the lock first
      Process.sleep(50)

      spawn(fn ->
        Locksmith.transaction(
          "/3.4",
          fn arg ->
            send(myself, arg)
          end,
          [:fast_fun]
        )
      end)

      assert_receive :fast_fun
      assert_receive :slow_fun, 500
    end

    test "N function call on same key will guarantee only one function is call at any given point in time" do
      t = :ets.new(:t, [:public, read_concurrency: true, write_concurrency: true])
      true = :ets.insert(t, {:c, 0})

      tasks =
        for i <- 1..101 do
          Task.async(fn ->
            Locksmith.transaction(
              "/2.5",
              fn v ->
                [c: c] = :ets.lookup(t, :c)

                Process.sleep(101 - v)

                true = :ets.insert(t, {:c, c + v})
              end,
              [i]
            )
          end)
        end

      Task.await_many(tasks, 10_000)

      assert [c: 5151] = :ets.lookup(t, :c)
    end
  end

  describe "Locksmith.transaction/4" do
    test "single function call on some key behaves same as calling apply",
      do: assert(:res = Locksmith.transaction("/4.1", LocksmithTest.Foo, :bar, [:res]))

    test "2 function call on same key will have call blocked until key is released" do
      myself = self()

      spawn(fn ->
        Locksmith.transaction(
          "/4.2",
          LocksmithTest.Foo,
          :sleepy_sending_bar,
          [myself, :slow_fun, 500]
        )
      end)

      # Ensure slow process acquires the lock first
      Process.sleep(50)

      spawn(fn ->
        Locksmith.transaction(
          "/4.2",
          LocksmithTest.Foo,
          :sending_bar,
          [myself, :fast_fun]
        )
      end)

      assert_receive :slow_fun, 500
      assert_receive :fast_fun
    end

    test "2 function call on different keys will have calls unaffected" do
      myself = self()

      spawn(fn ->
        Locksmith.transaction(
          "/4.3",
          LocksmithTest.Foo,
          :sleepy_sending_bar,
          [myself, :slow_fun, 500]
        )
      end)

      # Ensure slow process acquires the lock first
      Process.sleep(50)

      spawn(fn ->
        Locksmith.transaction(
          "/4.4",
          LocksmithTest.Foo,
          :sending_bar,
          [myself, :fast_fun]
        )
      end)

      assert_receive :fast_fun
      assert_receive :slow_fun, 500
    end

    test "N function call on same key will guarantee only one function is call at any given point in time" do
      t = :ets.new(:t, [:public, read_concurrency: true, write_concurrency: true])
      true = :ets.insert(t, {:c, 0})

      tasks =
        for i <- 1..101 do
          Task.async(fn ->
            Locksmith.transaction(
              "/4.5",
              LocksmithTest.Foo,
              :lookup_then_add,
              [t, :c, i]
            )
          end)
        end

      Task.await_many(tasks, 10_000)

      assert [c: 5151] = :ets.lookup(t, :c)
    end
  end

  defmodule Foo do
    def bar, do: :ok
    def bar(arg1), do: arg1

    def sending_bar(pid, arg1), do: send(pid, arg1)
    def sleepy_sending_bar(pid, arg1, delay), do: Process.send_after(pid, arg1, delay)

    def sleepy_bar(pid, msg, delay) do
      Process.sleep(delay)
      send(pid, msg)
    end

    def lookup_then_add(t, k, v) do
      [{^k, c}] = :ets.lookup(t, k)

      Process.sleep(101 - v)

      true = :ets.insert(t, {:c, c + v})
    end
  end
end
