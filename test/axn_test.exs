defmodule AxnTest do
  use ExUnit.Case

  describe "Axn DSL compilation" do
    test "module can use Axn macro" do
      # This should compile without errors
      defmodule TestActions do
        use Axn, telemetry_prefix: [:test, :actions]
      end

      # Module should exist
      assert Code.ensure_loaded?(TestActions)
    end

    test "empty action can be defined and compiled" do
      defmodule EmptyActionModule do
        use Axn, telemetry_prefix: [:test, :empty]

        action :ping do
          # Empty action - should compile
        end
      end

      assert Code.ensure_loaded?(EmptyActionModule)
      assert function_exported?(EmptyActionModule, :run, 3)
    end

    test "run/3 function is generated for modules using Axn" do
      defmodule RunFunctionModule do
        use Axn, telemetry_prefix: [:test, :run_function]

        action :test_action do
          # Empty action
        end
      end

      # Should have run/3 function
      assert function_exported?(RunFunctionModule, :run, 3)
    end

    test "action without steps returns ok with nil result" do
      defmodule NoStepsModule do
        use Axn, telemetry_prefix: [:test, :no_steps]

        action :empty_action do
          # No steps
        end
      end

      # Should return ok with nil since no steps set a result
      assert {:ok, nil} = NoStepsModule.run(:empty_action, %{}, %{})
    end

    test "undefined action returns error" do
      defmodule UndefinedActionModule do
        use Axn, telemetry_prefix: [:test, :undefined]

        action :existing_action do
          # Empty action
        end
      end

      # Should return error for non-existent action
      assert {:error, :action_not_found} = UndefinedActionModule.run(:non_existent, %{}, %{})
    end

    test "telemetry_prefix is stored correctly" do
      defmodule TelemetryModule do
        use Axn, telemetry_prefix: [:my_app, :test]

        action :test_action do
          # Empty action
        end
      end

      # We can't directly test the telemetry prefix storage yet,
      # but we can ensure the module compiles with it
      assert Code.ensure_loaded?(TelemetryModule)
    end
  end
end
