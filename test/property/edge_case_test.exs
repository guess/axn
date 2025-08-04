defmodule AxnEdgeCaseTest do
  @moduledoc """
  Edge case tests for Axn to verify robustness under unusual conditions.

  These tests cover boundary conditions, unusual inputs, and error scenarios
  that might not be covered by regular unit tests.
  """

  use ExUnit.Case
  import Axn.TestHelpers
  alias Axn.Context

  describe "context edge cases" do
    defmodule EdgeCaseActions do
      use Axn

      action :context_manipulation do
        step :manipulate_context

        def manipulate_context(ctx) do
          # Test that context manipulation works with edge case data
          ctx = Context.assign(ctx, :test_data, ctx.params)
          ctx = Context.put_private(ctx, :processed, true)
          {:halt, {:ok, ctx.assigns}}
        end
      end

      action :parameter_validation do
        step :cast_validate_params,
          schema: %{
            name: :string,
            age: :integer,
            email: :string,
            active: :boolean
          }

        step :handle_validation

        def handle_validation(ctx) do
          {:halt, {:ok, ctx.params}}
        end
      end
    end

    test "context handles empty data" do
      result = EdgeCaseActions.run(:context_manipulation, %{}, %{})
      assert {:ok, assigns} = result
      assert assigns.test_data == %{}
    end

    test "context handles very large data structures" do
      # Create a large nested structure
      large_data =
        1..100
        |> Enum.map(fn i ->
          {:"key_#{i}",
           %{
             nested: %{
               deep: %{
                 values: Enum.to_list(1..50),
                 more_data: "value_#{i}"
               }
             }
           }}
        end)
        |> Enum.into(%{})

      result = EdgeCaseActions.run(:context_manipulation, %{}, large_data)
      assert {:ok, assigns} = result
      assert assigns.test_data == large_data
    end

    test "context handles deeply nested structures" do
      # Create deeply nested structure
      deeply_nested =
        Enum.reduce(1..20, "final_value", fn i, acc ->
          %{:"level_#{i}" => acc}
        end)

      data = %{nested: deeply_nested}

      result = EdgeCaseActions.run(:context_manipulation, %{}, data)
      assert {:ok, assigns} = result
      assert assigns.test_data == data
    end

    test "parameter validation with edge case inputs" do
      edge_cases = [
        # Empty strings
        %{"name" => "", "age" => "0", "email" => "", "active" => "false"},
        # Very long strings
        %{
          "name" => String.duplicate("a", 10000),
          "email" => "test@example.com",
          "active" => "true"
        },
        # Unicode characters
        %{"name" => "José Müller 中文", "email" => "josé@münchen.de", "active" => "true"},
        # Boundary numbers
        %{"name" => "test", "age" => "0", "email" => "test@example.com", "active" => "false"},
        %{"name" => "test", "age" => "999999", "email" => "test@example.com", "active" => "true"},
        # Mixed valid/invalid
        %{"name" => "valid", "age" => "invalid", "email" => "test@example.com"}
      ]

      Enum.each(edge_cases, fn params ->
        result = EdgeCaseActions.run(:parameter_validation, %{}, params)

        # Should either succeed or fail gracefully with invalid_params
        case result do
          {:ok, _casted_params} -> :ok
          {:error, %{reason: :invalid_params}} -> :ok
          other -> flunk("Unexpected result for #{inspect(params)}: #{inspect(other)}")
        end
      end)
    end
  end

  describe "step pipeline edge cases" do
    defmodule PipelineEdgeCaseActions do
      use Axn

      action :empty_action do
        # Action with no steps - should succeed with nil result
      end

      action :single_step do
        step :handle_single

        def handle_single(_ctx) do
          {:halt, {:ok, "single_step_result"}}
        end
      end

      action :early_halt do
        step :halt_immediately
        step :never_reached

        def halt_immediately(_ctx) do
          {:halt, {:ok, "halted_early"}}
        end

        def never_reached(_ctx) do
          flunk("This step should never be reached")
        end
      end

      action :context_mutation_chain do
        step :add_field_1
        step :add_field_2
        step :add_field_3
        step :finalize

        def add_field_1(ctx) do
          {:cont, Context.assign(ctx, :field_1, "value_1")}
        end

        def add_field_2(ctx) do
          {:cont, Context.assign(ctx, :field_2, "value_2")}
        end

        def add_field_3(ctx) do
          {:cont, Context.assign(ctx, :field_3, "value_3")}
        end

        def finalize(ctx) do
          result = %{
            field_1: ctx.assigns.field_1,
            field_2: ctx.assigns.field_2,
            field_3: ctx.assigns.field_3,
            all_assigns: ctx.assigns
          }

          {:halt, {:ok, result}}
        end
      end
    end

    test "empty action succeeds with no steps" do
      result = PipelineEdgeCaseActions.run(:empty_action, %{}, %{})
      assert {:ok, nil} = result
    end

    test "single step action works correctly" do
      result = PipelineEdgeCaseActions.run(:single_step, %{}, %{})
      assert {:ok, "single_step_result"} = result
    end

    test "early halt prevents subsequent steps from running" do
      result = PipelineEdgeCaseActions.run(:early_halt, %{}, %{})
      assert {:ok, "halted_early"} = result
    end

    test "context mutations accumulate correctly through pipeline" do
      result = PipelineEdgeCaseActions.run(:context_mutation_chain, %{}, %{})

      assert {:ok, final_result} = result
      assert final_result.field_1 == "value_1"
      assert final_result.field_2 == "value_2"
      assert final_result.field_3 == "value_3"

      # All fields should be present in the final assigns
      assert final_result.all_assigns.field_1 == "value_1"
      assert final_result.all_assigns.field_2 == "value_2"
      assert final_result.all_assigns.field_3 == "value_3"
    end
  end

  describe "error handling edge cases" do
    defmodule ErrorEdgeCaseActions do
      use Axn

      action :various_error_types do
        step :handle_errors

        def handle_errors(ctx) do
          case Map.get(ctx.params, :error_type) do
            :atom_error ->
              {:halt, {:error, :simple_atom}}

            :string_error ->
              {:halt, {:error, "string error"}}

            :complex_error ->
              {:halt, {:error, %{type: :complex, message: "Complex error", code: 400}}}

            :nested_error ->
              {:halt, {:error, %{reason: :nested, details: %{inner: "Deep error"}}}}

            :exception ->
              raise ArgumentError, "Test exception"

            :invalid_return ->
              "invalid return format"

            :malformed_tuple ->
              {:invalid, "malformed"}

            _ ->
              {:halt, {:ok, "success"}}
          end
        end
      end
    end

    test "handles various error formats correctly" do
      error_cases = [
        {:atom_error, {:error, :simple_atom}},
        {:string_error, {:error, "string error"}},
        {:complex_error, {:error, %{type: :complex, message: "Complex error", code: 400}}},
        {:nested_error, {:error, %{reason: :nested, details: %{inner: "Deep error"}}}},
        {:exception, {:error, %{reason: :step_exception, message: "Test exception"}}},
        {:invalid_return,
         {:error,
          %{
            reason: :step_exception,
            message: "no case clause matching: \"invalid return format\""
          }}},
        {:malformed_tuple,
         {:error,
          %{
            reason: :step_exception,
            message: "no case clause matching: {:invalid, \"malformed\"}"
          }}},
        {:success, {:ok, "success"}}
      ]

      Enum.each(error_cases, fn {input, expected} ->
        result = ErrorEdgeCaseActions.run(:various_error_types, %{}, %{error_type: input})

        assert result == expected,
               "Failed for input #{inspect(input)}. Expected: #{inspect(expected)}, Got: #{inspect(result)}"
      end)
    end
  end

  describe "telemetry edge cases" do
    defmodule TelemetryEdgeCaseActions do
      use Axn, telemetry_prefix: [:edge_case_test]

      action :telemetry_with_edge_data do
        step :handle_edge_data

        def handle_edge_data(ctx) do
          case Map.get(ctx.params, :scenario) do
            :success -> {:halt, {:ok, "success"}}
            :error -> {:halt, {:error, :test_error}}
            :exception -> raise "Test exception"
            _ -> {:halt, {:ok, "default"}}
          end
        end
      end
    end

    test "telemetry works with various user data scenarios" do
      scenarios = [
        # No user
        {%{}, :success, nil},
        # User with string ID
        {%{current_user: %{id: "string_id"}}, :success, "string_id"},
        # User with integer ID (converted to string by telemetry)
        {%{current_user: %{id: 12345}}, :success, "12345"},
        # User with nil ID
        {%{current_user: %{id: nil}}, :success, nil},
        # User without ID field
        {%{current_user: %{name: "John"}}, :success, nil},
        # Error scenarios (ID converted to string by telemetry)
        {%{current_user: %{id: 999}}, :error, "999"},
        {%{}, :error, nil}
      ]

      Enum.each(scenarios, fn {assigns, scenario, expected_user_id} ->
        events = capture_telemetry([[:edge_case_test]])

        result =
          TelemetryEdgeCaseActions.run(:telemetry_with_edge_data, assigns, %{scenario: scenario})

        captured = events.()
        assert length(captured) == 2, "Should have start and stop events for scenario #{scenario}"

        {_stop_event, _measurements, stop_metadata} =
          Enum.find(captured, fn {event, _, _} ->
            List.last(event) == :stop
          end)

        assert stop_metadata.user_id == expected_user_id

        case scenario do
          :success -> assert {:ok, "success"} = result
          :error -> assert {:error, :test_error} = result
          :exception -> assert {:error, %{reason: :step_exception}} = result
          _ -> assert {:ok, "default"} = result
        end
      end)
    end
  end

  describe "memory and performance edge cases" do
    defmodule PerformanceEdgeCaseActions do
      use Axn

      action :large_context_processing do
        step :create_large_context
        step :process_large_context

        def create_large_context(ctx) do
          # Create a moderately large context to test memory handling
          large_assigns =
            1..1000
            |> Enum.map(fn i -> {:"key_#{i}", "value_#{i}"} end)
            |> Enum.into(%{})

          {:cont, Context.assign(ctx, large_assigns)}
        end

        def process_large_context(ctx) do
          # Process the large context
          key_count = ctx.assigns |> Map.keys() |> length()
          {:halt, {:ok, %{processed_keys: key_count}}}
        end
      end

      action :rapid_mutations do
        step :perform_mutations

        def perform_mutations(ctx) do
          # Perform many rapid context mutations
          final_ctx =
            1..100
            |> Enum.reduce(ctx, fn i, acc_ctx ->
              Context.assign(acc_ctx, :"rapid_#{i}", i)
            end)

          mutation_count = final_ctx.assigns |> Map.keys() |> length()
          {:halt, {:ok, %{mutations: mutation_count}}}
        end
      end
    end

    test "handles large context data efficiently" do
      result = PerformanceEdgeCaseActions.run(:large_context_processing, %{}, %{})
      assert {:ok, %{processed_keys: count}} = result
      assert count >= 1000
    end

    test "handles rapid context mutations" do
      result = PerformanceEdgeCaseActions.run(:rapid_mutations, %{}, %{})
      assert {:ok, %{mutations: count}} = result
      assert count >= 100
    end
  end

  describe "context helper edge cases" do
    defmodule ContextHelperEdgeCaseActions do
      use Axn

      action :test_helper_edge_cases do
        step :test_assign_edge_cases
        step :test_private_edge_cases

        def test_assign_edge_cases(ctx) do
          # Test edge cases in assign patterns
          ctx = Context.assign(ctx, :nil_value, nil)
          ctx = Context.assign(ctx, :empty_map, %{})
          ctx = Context.assign(ctx, :empty_list, [])
          # Empty map assign
          ctx = Context.assign(ctx, %{})
          # Empty keyword list
          ctx = Context.assign(ctx, [])

          {:cont, ctx}
        end

        def test_private_edge_cases(ctx) do
          # Test edge cases in private data handling
          ctx = Context.put_private(ctx, :nil_private_value, nil)
          ctx = Context.put_private(ctx, :complex_private, %{nested: %{data: [1, 2, 3]}})

          # Test getting with defaults
          nil_value = Context.get_private(ctx, :nil_private_value, "default")
          missing_value = Context.get_private(ctx, :nonexistent_key, "default")
          complex_value = Context.get_private(ctx, :complex_private)

          result = %{
            nil_value: nil_value,
            missing_value: missing_value,
            complex_value: complex_value,
            assigns: ctx.assigns
          }

          {:halt, {:ok, result}}
        end
      end
    end

    test "context helpers handle edge cases correctly" do
      result = ContextHelperEdgeCaseActions.run(:test_helper_edge_cases, %{}, %{})

      assert {:ok, final_result} = result

      # Check assign edge cases
      assert final_result.assigns.nil_value == nil
      assert final_result.assigns.empty_map == %{}
      assert final_result.assigns.empty_list == []

      # Check private edge cases
      # nil value returned as-is, not default
      assert final_result.nil_value == nil
      assert final_result.missing_value == "default"
      assert final_result.complex_value == %{nested: %{data: [1, 2, 3]}}
    end
  end
end
