defmodule Axn.ErrorHandlingTest do
  use ExUnit.Case

  describe "error propagation through pipeline" do
    test "error in first step stops pipeline and preserves error information" do
      defmodule FirstStepErrorModule do
        use Axn, telemetry_prefix: [:test, :first_error]

        action :first_step_fails do
          step :failing_step
          step :never_reached
          step :also_never_reached

          def failing_step(_ctx) do
            {:halt, {:error, %{reason: :custom_error, details: "first step failed"}}}
          end

          def never_reached(ctx) do
            {:cont, put_result(ctx, "should not reach")}
          end

          def also_never_reached(ctx) do
            {:cont, put_result(ctx, "definitely should not reach")}
          end
        end
      end

      assert {:error, %{reason: :custom_error, details: "first step failed"}} =
               FirstStepErrorModule.run(:first_step_fails, %{}, %{})
    end

    test "error in middle step stops pipeline and includes step context" do
      defmodule MiddleStepErrorModule do
        use Axn, telemetry_prefix: [:test, :middle_error]

        action :middle_step_fails do
          step :first_step
          step :failing_step
          step :never_reached

          def first_step(ctx) do
            {:cont, put_private(ctx, :executed_steps, [:first_step])}
          end

          def failing_step(ctx) do
            executed = get_private(ctx, :executed_steps, [])

            {:halt,
             {:error, %{reason: :middle_failure, executed_steps: executed, step: :failing_step}}}
          end

          def never_reached(ctx) do
            {:cont, put_result(ctx, "should not reach")}
          end
        end
      end

      assert {:error,
              %{reason: :middle_failure, executed_steps: [:first_step], step: :failing_step}} =
               MiddleStepErrorModule.run(:middle_step_fails, %{}, %{})
    end

    test "error details are preserved through multiple error sources" do
      defmodule MultipleErrorSourcesModule do
        use Axn, telemetry_prefix: [:test, :multi_error]

        action :validation_then_business_error do
          step :cast_validate_params, schema: %{email!: :string, age!: :integer}
          step :business_validation

          def business_validation(ctx) do
            if ctx.params.age < 18 do
              {:halt,
               {:error,
                %{
                  reason: :business_rule_violation,
                  rule: :minimum_age,
                  provided_age: ctx.params.age,
                  minimum_required: 18
                }}}
            else
              {:cont, ctx}
            end
          end
        end
      end

      # Test validation error (should happen first)
      assert {:error, %{reason: :invalid_params, changeset: changeset}} =
               MultipleErrorSourcesModule.run(:validation_then_business_error, %{}, %{
                 "email" => "test@example.com"
               })

      refute changeset.valid?

      # Test business rule error (validation passes, business rule fails)
      assert {:error,
              %{
                reason: :business_rule_violation,
                rule: :minimum_age,
                provided_age: 15,
                minimum_required: 18
              }} =
               MultipleErrorSourcesModule.run(:validation_then_business_error, %{}, %{
                 "email" => "test@example.com",
                 "age" => "15"
               })
    end

    test "external step errors are propagated correctly" do
      defmodule ExternalErrorModule do
        def failing_external_step(_ctx, _opts) do
          {:halt, {:error, %{reason: :external_service_error, service: :payment_gateway}}}
        end
      end

      defmodule WithExternalErrorModule do
        use Axn, telemetry_prefix: [:test, :external_error]

        action :external_step_fails do
          step :setup_step
          step {ExternalErrorModule, :failing_external_step}
          step :cleanup_step

          def setup_step(ctx) do
            {:cont, put_private(ctx, :setup_complete, true)}
          end

          def cleanup_step(ctx) do
            {:cont, put_result(ctx, "cleanup complete")}
          end
        end
      end

      assert {:error, %{reason: :external_service_error, service: :payment_gateway}} =
               WithExternalErrorModule.run(:external_step_fails, %{}, %{})
    end
  end

  describe "basic error handling" do
    test "errors are passed through unchanged" do
      defmodule BasicErrorModule do
        use Axn, telemetry_prefix: [:test, :basic_error]

        action :process_payment do
          step :validate_payment_info

          def validate_payment_info(_ctx) do
            {:halt, {:error, %{reason: :validation_failed, details: "Payment info invalid"}}}
          end
        end
      end

      {:error, error} = BasicErrorModule.run(:process_payment, %{}, %{})

      assert error.reason == :validation_failed
      assert error.details == "Payment info invalid"
    end
  end

  describe "graceful exception handling" do
    test "step exceptions are caught and converted to error tuples" do
      defmodule ExceptionHandlingModule do
        use Axn, telemetry_prefix: [:test, :exceptions]

        action :step_raises_exception do
          step :normal_step
          step :exception_step
          step :never_reached

          def normal_step(ctx) do
            {:cont, put_private(ctx, :normal_executed, true)}
          end

          def exception_step(_ctx) do
            raise ArgumentError, "Something went wrong in the step"
          end

          def never_reached(ctx) do
            {:cont, put_result(ctx, "should not reach")}
          end
        end
      end

      {:error, error} = ExceptionHandlingModule.run(:step_raises_exception, %{}, %{})

      assert error == :step_exception
    end

    test "external step exceptions are handled gracefully" do
      defmodule ExternalExceptionModule do
        def raising_step(_ctx, _opts) do
          raise RuntimeError, "External step failed with sensitive data: password123"
        end
      end

      defmodule WithExternalExceptionModule do
        use Axn, telemetry_prefix: [:test, :external_exception]

        action :external_step_raises do
          step :setup
          step {ExternalExceptionModule, :raising_step}
          step :cleanup

          def setup(ctx) do
            {:cont, put_private(ctx, :setup_done, true)}
          end

          def cleanup(ctx) do
            {:cont, put_result(ctx, "cleanup done")}
          end
        end
      end

      {:error, error} = WithExternalExceptionModule.run(:external_step_raises, %{}, %{})

      assert error == :step_exception
    end

    test "multiple exception types are handled consistently" do
      defmodule MultipleExceptionTypesModule do
        use Axn, telemetry_prefix: [:test, :multi_exceptions]

        action :argument_error do
          step :raise_argument_error
          def raise_argument_error(_ctx), do: raise(ArgumentError, "Invalid argument")
        end

        action :runtime_error do
          step :raise_runtime_error
          def raise_runtime_error(_ctx), do: raise(RuntimeError, "Runtime failure")
        end

        action :custom_error do
          step :raise_custom_error
          def raise_custom_error(_ctx), do: raise("Custom error message")
        end

        action :system_error do
          step :raise_system_error
          def raise_system_error(_ctx), do: File.read!("/nonexistent/file")
        end
      end

      # All exception types return the same simple error
      assert {:error, :step_exception} = MultipleExceptionTypesModule.run(:argument_error, %{}, %{})
      assert {:error, :step_exception} = MultipleExceptionTypesModule.run(:runtime_error, %{}, %{})
      assert {:error, :step_exception} = MultipleExceptionTypesModule.run(:custom_error, %{}, %{})
      assert {:error, :step_exception} = MultipleExceptionTypesModule.run(:system_error, %{}, %{})
    end


    test "pipeline continues to work after exceptions in other actions" do
      defmodule PipelineResilienceModule do
        use Axn, telemetry_prefix: [:test, :resilience]

        action :working_action do
          step :work
          def work(ctx), do: {:cont, put_result(ctx, "success")}
        end

        action :failing_action do
          step :fail
          def fail(_ctx), do: raise("This action fails")
        end

        action :another_working_action do
          step :more_work
          def more_work(ctx), do: {:cont, put_result(ctx, "also success")}
        end
      end

      # First action should work
      assert {:ok, "success"} = PipelineResilienceModule.run(:working_action, %{}, %{})

      # Second action should fail gracefully
      assert {:error, :step_exception} =
               PipelineResilienceModule.run(:failing_action, %{}, %{})

      # Third action should still work (pipeline not corrupted)
      assert {:ok, "also success"} =
               PipelineResilienceModule.run(:another_working_action, %{}, %{})
    end
  end
end
