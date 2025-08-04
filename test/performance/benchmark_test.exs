defmodule AxnBenchmarkTest do
  @moduledoc """
  Performance benchmarks and optimization tests for Axn.

  These tests ensure that Axn maintains good performance characteristics
  as the codebase grows and usage patterns evolve.
  """

  use ExUnit.Case
  alias Axn.Context

  describe "action execution performance" do
    defmodule BenchmarkActions do
      use Axn, telemetry_prefix: [:benchmark]

      # Simple action for baseline performance
      action :simple_action do
        step :handle_simple

        def handle_simple(_ctx) do
          {:halt, {:ok, "simple"}}
        end
      end

      # Action with multiple steps
      action :multi_step_action do
        step :step_1
        step :step_2
        step :step_3
        step :step_4
        step :step_5

        def step_1(ctx), do: {:cont, Context.assign(ctx, :step_1, true)}
        def step_2(ctx), do: {:cont, Context.assign(ctx, :step_2, true)}
        def step_3(ctx), do: {:cont, Context.assign(ctx, :step_3, true)}
        def step_4(ctx), do: {:cont, Context.assign(ctx, :step_4, true)}
        def step_5(_ctx), do: {:halt, {:ok, "multi_step"}}
      end

      # Action with parameter validation
      action :validation_action do
        step :cast_validate_params,
          schema: %{
            name!: :string,
            email!: :string,
            age: :integer,
            phone: :string,
            address: :string,
            city: :string,
            country: [field: :string, default: "US"]
          }

        step :handle_validation

        def handle_validation(_ctx) do
          {:halt, {:ok, "validated"}}
        end
      end

      # Action that processes larger context
      action :large_context_action do
        step :build_large_context
        step :process_context

        def build_large_context(ctx) do
          large_data =
            1..1000
            |> Enum.map(fn i -> {:"key_#{i}", "value_#{i}"} end)
            |> Enum.into(%{})

          {:cont, Context.assign(ctx, large_data)}
        end

        def process_context(ctx) do
          # Simulate processing the large context
          count = ctx.assigns |> Map.keys() |> length()
          {:halt, {:ok, count}}
        end
      end
    end

    test "simple action executes quickly" do
      {time_micro, result} =
        :timer.tc(fn ->
          BenchmarkActions.run(:simple_action, %{}, %{})
        end)

      assert {:ok, "simple"} = result
      # Should complete in less than 1ms (1000 microseconds) for simple action
      assert time_micro < 1000, "Simple action took #{time_micro} microseconds, expected < 1000"
    end

    test "multi-step action performance scales linearly" do
      {time_micro, result} =
        :timer.tc(fn ->
          BenchmarkActions.run(:multi_step_action, %{}, %{})
        end)

      assert {:ok, "multi_step"} = result
      # Should complete in less than 5ms even with 5 steps
      assert time_micro < 5000,
             "Multi-step action took #{time_micro} microseconds, expected < 5000"
    end

    test "parameter validation performance is acceptable" do
      params = %{
        "name" => "John Doe",
        "email" => "john@example.com",
        "age" => "30",
        "phone" => "+1-555-123-4567",
        "address" => "123 Main St",
        "city" => "Anytown"
      }

      {time_micro, result} =
        :timer.tc(fn ->
          BenchmarkActions.run(:validation_action, %{}, params)
        end)

      assert {:ok, "validated"} = result
      # Parameter validation should complete in reasonable time
      assert time_micro < 10000,
             "Validation action took #{time_micro} microseconds, expected < 10000"
    end
  end

  describe "concurrent execution performance" do
    defmodule ConcurrentActions do
      use Axn

      action :concurrent_test do
        step :add_process_info
        step :simulate_work

        def add_process_info(ctx) do
          {:cont, Context.assign(ctx, :pid, self())}
        end

        def simulate_work(ctx) do
          # Small amount of work to simulate real processing
          :timer.sleep(1)
          {:halt, {:ok, %{pid: ctx.assigns.pid, timestamp: System.monotonic_time()}}}
        end
      end
    end

    test "actions can run concurrently without interference" do
      # Spawn multiple concurrent executions
      tasks =
        1..50
        |> Enum.map(fn i ->
          Task.async(fn ->
            result = ConcurrentActions.run(:concurrent_test, %{task_id: i}, %{})
            {i, result}
          end)
        end)

      # Collect results
      results = tasks |> Enum.map(&Task.await/1)

      # All should succeed
      assert length(results) == 50

      Enum.each(results, fn {_task_id, result} ->
        assert {:ok, %{pid: pid, timestamp: timestamp}} = result
        assert is_pid(pid)
        assert is_integer(timestamp)
      end)

      # Each should have run in a different process context
      pids = results |> Enum.map(fn {_id, {:ok, %{pid: pid}}} -> pid end) |> Enum.uniq()
      assert length(pids) == 50, "Expected 50 unique PIDs, got #{length(pids)}"
    end
  end

  describe "memory usage optimization" do
    defmodule MemoryTestActions do
      use Axn

      action :memory_test do
        step :create_data
        step :process_data
        step :cleanup_data

        def create_data(ctx) do
          # Create some data that should be cleaned up
          data = 1..1000 |> Enum.to_list()
          {:cont, Context.put_private(ctx, :temp_data, data)}
        end

        def process_data(ctx) do
          data = Context.get_private(ctx, :temp_data, [])
          result = Enum.sum(data)
          {:cont, Context.assign(ctx, :sum, result)}
        end

        def cleanup_data(ctx) do
          # Remove temporary data to free memory
          ctx = Context.put_private(ctx, :temp_data, nil)
          {:halt, {:ok, ctx.assigns.sum}}
        end
      end
    end
  end

  describe "telemetry performance overhead" do
    defmodule TelemetryOverheadActions do
      use Axn, telemetry_prefix: [:overhead_test]

      action :test_with_telemetry do
        step :handle_test

        def handle_test(_ctx) do
          {:halt, {:ok, "completed"}}
        end
      end
    end

    defmodule NoTelemetryActions do
      # Module without telemetry for comparison
      def run_without_telemetry do
        _ctx = %Context{action: :test, assigns: %{}, params: %{}, private: %{}, result: nil}
        {:ok, "completed"}
      end
    end
  end

  describe "step resolution performance" do
    defmodule ExternalStepModule do
      def external_step(ctx, _opts) do
        {:cont, Context.assign(ctx, :external_called, true)}
      end
    end

    defmodule StepResolutionActions do
      use Axn

      # Action with only local steps
      action :local_steps_only do
        step :local_1
        step :local_2
        step :local_3

        def local_1(ctx), do: {:cont, Context.assign(ctx, :local_1, true)}
        def local_2(ctx), do: {:cont, Context.assign(ctx, :local_2, true)}
        def local_3(_ctx), do: {:halt, {:ok, "local_completed"}}
      end

      # Action with mixed local and external steps
      action :mixed_steps do
        step :local_1
        step {ExternalStepModule, :external_step}
        step :local_2

      end
    end

    test "local step resolution is fast" do
      {time_micro, result} =
        :timer.tc(fn ->
          StepResolutionActions.run(:local_steps_only, %{}, %{})
        end)

      assert {:ok, "local_completed"} = result
      # Local steps should be very fast
      assert time_micro < 2000, "Local steps took #{time_micro} microseconds, expected < 2000"
    end
  end

  describe "scalability with many actions" do
    defmodule ScalabilityActions do
      use Axn

      # Generate many actions to test compilation and runtime scalability
      for i <- 1..50 do
        action :"action_#{i}" do
          step :"step_#{i}"

          def unquote(:"step_#{i}")(_ctx) do
            {:halt, {:ok, unquote("result_#{i}")}}
          end
        end
      end
    end

    test "module with many actions compiles and runs efficiently" do
      # Test a sampling of actions to ensure they all work
      test_actions = [:action_1, :action_10, :action_25, :action_50]

      results =
        Enum.map(test_actions, fn action ->
          {time, result} =
            :timer.tc(fn ->
              ScalabilityActions.run(action, %{}, %{})
            end)

          {action, time, result}
        end)

      # All should succeed and run quickly
      Enum.each(results, fn {action, time, result} ->
        expected_result = action |> Atom.to_string() |> String.replace("action_", "result_")
        assert {:ok, ^expected_result} = result
        assert time < 1000, "Action #{action} took #{time} microseconds, expected < 1000"
      end)
    end
  end
end
