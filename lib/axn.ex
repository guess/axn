defmodule Axn do
  @moduledoc """
  Axn - A clean, step-based DSL library for defining actions with parameter validation,
  authorization, telemetry, and custom business logic.
  """

  alias Axn.Steps.CastValidateParams

  @doc """
  Sets up a module to use the Axn DSL for defining actions.

  ## Options

  * `:telemetry_prefix` - List of atoms that form the telemetry event prefix.
    Defaults to the module name converted to atoms.

  ## Examples

      defmodule MyApp.UserActions do
        use Axn, telemetry_prefix: [:my_app, :users]

        action :create_user do
          # Action definition
        end
      end
  """
  defmacro __using__(opts) do
    telemetry_prefix = Keyword.get(opts, :telemetry_prefix, [:axn])

    quote do
      import Axn, only: [action: 2, step: 1, step: 2]
      import Axn.Context

      alias Axn.Context

      @telemetry_prefix unquote(telemetry_prefix)
      @actions []
      @current_action nil
      @steps []

      @before_compile Axn
    end
  end

  @doc """
  Defines an action with its steps.

  ## Examples

      action :create_user do
        step :cast_validate_params, schema: %{name!: :string}
        step :authorize, &can_create_users?/1
        step :handle_create
      end
  """
  defmacro action(name, do: block) do
    quote do
      @current_action unquote(name)
      @steps []

      unquote(block)

      @actions [{unquote(name), Enum.reverse(@steps)} | @actions]
      @current_action nil
      @steps []
    end
  end

  @doc """
  Defines a step within an action.

  ## Examples

      step :my_step
      step :my_step, option: value
      step {ExternalModule, :external_step}, option: value
  """
  defmacro step(step_spec, opts \\ []) do
    quote do
      @steps [{unquote(step_spec), unquote(opts)} | @steps]
    end
  end

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      @actions Enum.reverse(@actions)

      unquote(generate_run_function())
      unquote(generate_result_helpers())
      unquote(generate_pipeline_functions())
      unquote(generate_telemetry_functions())
      unquote(generate_step_execution_functions())
    end
  end

  defp generate_run_function do
    quote do
      @doc """
      Runs an action with the given assigns and raw parameters.

      Returns `{:ok, result}` on success or `{:error, reason}` on failure.
      """
      def run(action_name, assigns, raw_params) do
        case run_action_pipeline(action_name, assigns, raw_params) do
          %Axn.Context{result: result} -> normalize_result(result)
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  defp generate_result_helpers do
    quote do
      defp normalize_result({:ok, value}), do: {:ok, value}
      defp normalize_result({:error, reason}), do: {:error, reason}
      defp normalize_result(nil), do: {:ok, nil}
      defp normalize_result(other), do: {:ok, other}

      defp find_action(action_name) do
        case Enum.find(@actions, fn {name, _steps} -> name == action_name end) do
          {_name, steps} -> {:ok, steps}
          nil -> {:error, :action_not_found}
        end
      end
    end
  end

  defp generate_pipeline_functions do
    quote do
      defp run_action_pipeline(action_name, assigns, raw_params) do
        case find_action(action_name) do
          {:ok, steps} ->
            ctx = %Axn.Context{
              action: action_name,
              assigns: assigns,
              params: raw_params
            }

            run_action_with_telemetry(ctx, steps)

          {:error, reason} ->
            {:error, reason}
        end
      end

      defp run_step_pipeline(steps, %Axn.Context{} = ctx) do
        Enum.reduce_while(steps, ctx, fn step, acc_ctx ->
          case apply_step(step, acc_ctx) do
            {:cont, new_ctx} -> {:cont, new_ctx}
            {:halt, result} -> {:halt, %{acc_ctx | result: result}}
          end
        end)
      end
    end
  end

  defp generate_telemetry_functions do
    quote do
      defp run_action_with_telemetry(%Axn.Context{} = ctx, steps) do
        metadata = extract_safe_metadata(ctx)

        try do
          :telemetry.span(
            @telemetry_prefix,
            metadata,
            fn ->
              result_ctx = run_step_pipeline(steps, ctx)
              final_metadata = extract_safe_metadata(result_ctx)
              {result_ctx, final_metadata}
            end
          )
        rescue
          exception ->
            %{
              ctx
              | result: {:error, %{reason: :step_exception, message: Exception.message(exception)}}
            }
        end
      end

      defp extract_safe_metadata(%Axn.Context{} = ctx) do
        %{
          action: ctx.action,
          user_id: get_user_id(ctx),
          result_type: if(match?({:error, _}, ctx.result), do: :error, else: :ok)
        }
      end

      defp get_user_id(%Axn.Context{assigns: %{current_user: %{id: id}}}) when is_binary(id) or is_integer(id),
        do: to_string(id)

      defp get_user_id(_), do: nil
    end
  end

  defp generate_step_execution_functions do
    quote do
      defp apply_step({step_name, opts}, %Axn.Context{} = ctx) when is_atom(step_name) do
        case step_name do
          :cast_validate_params ->
            CastValidateParams.cast_validate_params(ctx, opts)

          _ ->
            apply_step_function(__MODULE__, step_name, ctx, opts)
        end
      end

      defp apply_step({{module, function}, opts}, %Axn.Context{} = ctx) do
        apply_step_function(module, function, ctx, opts)
      end

      defp apply_step_function(module, function, ctx, opts) do
        cond do
          function_exported?(module, function, 2) ->
            apply(module, function, [ctx, opts])

          function_exported?(module, function, 1) ->
            apply(module, function, [ctx])

          true ->
            {:halt, {:error, :step_not_found}}
        end
      end
    end
  end
end
