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

  describe "action/2 macro functionality" do
    test "multiple actions with various features" do
      defmodule CompleteActionModule do
        use Axn, telemetry_prefix: [:test, :complete]

        action :first_action do
        end

        action :second_action do
          step :helper_step

          def helper_function(data), do: String.upcase(data)

          def helper_step(ctx) do
            result = helper_function("hello")
            {:cont, put_result(ctx, result)}
          end
        end

        action :third_action do
        end
      end

      # Multiple actions callable
      assert {:ok, nil} = CompleteActionModule.run(:first_action, %{}, %{})
      assert {:ok, "HELLO"} = CompleteActionModule.run(:second_action, %{}, %{})
      assert {:ok, nil} = CompleteActionModule.run(:third_action, %{}, %{})

      # Non-existent actions return error
      assert {:error, :action_not_found} = CompleteActionModule.run(:missing, %{}, %{})

      # Helper functions are accessible
      assert CompleteActionModule.helper_function("test") == "TEST"
    end
  end

  describe "step/1 and step/2 macros functionality" do
    test "steps with and without options, plus halt behavior" do
      defmodule StepTestModule do
        use Axn, telemetry_prefix: [:test, :steps]

        action :single_step do
          step :single_step
          def single_step(ctx), do: {:cont, put_result(ctx, "single step")}
        end

        action :multi_step_with_options do
          step :multi_first_step
          step :multi_second_step, multiplier: 3
          step :multi_final_step

          def multi_first_step(ctx), do: {:cont, assign(ctx, :value, 5)}

          def multi_second_step(ctx, opts) do
            new_value = ctx.assigns[:value] * opts[:multiplier]
            {:cont, assign(ctx, :result, new_value)}
          end

          def multi_final_step(ctx), do: {:cont, put_result(ctx, ctx.assigns[:result])}
        end

        action :halt_success do
          step :first_step
          step :halting_step
          step :never_reached

          def first_step(ctx), do: {:cont, assign(ctx, :done, true)}
          def halting_step(_ctx), do: {:halt, {:ok, "halted"}}
          def never_reached(ctx), do: {:cont, put_result(ctx, "unreachable")}
        end

        action :halt_error do
          step :error_step
          def error_step(_ctx), do: {:halt, {:error, "failed"}}
        end
      end

      # Single step
      assert {:ok, "single step"} = StepTestModule.run(:single_step, %{}, %{})

      # Multiple steps with options
      assert {:ok, 15} = StepTestModule.run(:multi_step_with_options, %{}, %{})

      # Halt with success
      assert {:ok, "halted"} = StepTestModule.run(:halt_success, %{}, %{})

      # Halt with error
      assert {:error, "failed"} = StepTestModule.run(:halt_error, %{}, %{})
    end

    test "external step specification" do
      defmodule ExternalStepModule do
        import Axn.Context

        def external_step(ctx, opts) do
          message = Keyword.get(opts, :message, "external")
          {:cont, put_result(ctx, message)}
        end
      end

      defmodule WithExternalStepModule do
        use Axn, telemetry_prefix: [:test, :external]

        action :use_external do
          step {ExternalStepModule, :external_step}, message: "from external"
        end
      end

      assert {:ok, "from external"} = WithExternalStepModule.run(:use_external, %{}, %{})
    end
  end

  describe "step pipeline execution" do
    test "context flow, execution order, and data access" do
      defmodule PipelineTestModule do
        use Axn, telemetry_prefix: [:test, :pipeline]

        action :context_flow do
          step :check_inputs
          step :build_result

          def check_inputs(ctx) do
            # Verify we can access raw_params, assigns, and action name
            raw_params = get_private(ctx, :raw_params)
            assigns = ctx.assigns
            action_name = ctx.action

            data = %{raw_params: raw_params, assigns: assigns, action: action_name}
            {:cont, assign(ctx, :input_data, data)}
          end

          def build_result(ctx) do
            result = %{
              message: "processed",
              input_data: ctx.assigns[:input_data]
            }

            {:cont, put_result(ctx, result)}
          end
        end

        action :execution_order do
          step :order_step_one
          step :order_step_two
          step :order_step_three

          def order_step_one(ctx) do
            order = get_private(ctx, :order, [])
            {:cont, put_private(ctx, :order, order ++ [1])}
          end

          def order_step_two(ctx) do
            order = get_private(ctx, :order, [])
            {:cont, put_private(ctx, :order, order ++ [2])}
          end

          def order_step_three(ctx) do
            order = get_private(ctx, :order, [])
            {:cont, put_result(ctx, order ++ [3])}
          end
        end

        action :halt_interrupts_pipeline do
          step :halt_step_one
          step :halting_step
          step :never_reached

          def halt_step_one(ctx), do: {:cont, put_private(ctx, :executed, [:step_one])}

          def halting_step(ctx) do
            executed = get_private(ctx, :executed, [])
            {:halt, {:ok, executed ++ [:halting_step]}}
          end

          def never_reached(ctx), do: {:cont, put_result(ctx, "should not reach")}
        end
      end

      # Test context flow and data access
      raw_params = %{"name" => "John"}
      assigns = %{user_id: 123}
      {:ok, result} = PipelineTestModule.run(:context_flow, assigns, raw_params)

      assert result.message == "processed"
      assert result.input_data.raw_params == raw_params
      assert result.input_data.assigns == assigns
      assert result.input_data.action == :context_flow

      # Test execution order
      assert {:ok, [1, 2, 3]} = PipelineTestModule.run(:execution_order, %{}, %{})

      # Test pipeline halt
      assert {:ok, [:step_one, :halting_step]} =
               PipelineTestModule.run(:halt_interrupts_pipeline, %{}, %{})
    end
  end
end
