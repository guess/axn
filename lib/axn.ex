defmodule Axn do
  @moduledoc """
  Axn - A clean, step-based DSL library for defining actions with parameter validation,
  authorization, telemetry, and custom business logic.
  """

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
    telemetry_prefix = Keyword.get(opts, :telemetry_prefix, [])

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

      @doc """
      Runs an action with the given assigns and raw parameters.

      Returns `{:ok, result}` on success or `{:error, reason}` on failure.
      """
      def run(action_name, assigns, raw_params) do
        case run_action_pipeline(action_name, assigns, raw_params) do
          %Axn.Context{result: {:ok, value}} -> {:ok, value}
          %Axn.Context{result: {:error, reason}} -> {:error, reason}
          %Axn.Context{result: result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end
      end

      defp run_action_pipeline(action_name, assigns, raw_params) do
        case find_action(action_name) do
          {:ok, steps} ->
            ctx = %Axn.Context{
              action: action_name,
              assigns: assigns,
              private: %{raw_params: raw_params}
            }

            run_step_pipeline(steps, ctx)

          {:error, reason} ->
            {:error, reason}
        end
      end

      defp find_action(action_name) do
        case Enum.find(@actions, fn {name, _steps} -> name == action_name end) do
          {_name, steps} -> {:ok, steps}
          nil -> {:error, :action_not_found}
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

      defp apply_step({step_name, opts}, %Axn.Context{} = ctx) when is_atom(step_name) do
        apply_step_function(__MODULE__, step_name, ctx, opts, :step_not_found)
      end

      defp apply_step({{module, function}, opts}, %Axn.Context{} = ctx) do
        apply_step_function(module, function, ctx, opts, :external_step_not_found)
      end

      defp apply_step_function(module, function, ctx, opts, error_type) do
        cond do
          function_exported?(module, function, 2) -> 
            apply(module, function, [ctx, opts])
          function_exported?(module, function, 1) -> 
            apply(module, function, [ctx])
          true -> 
            {:halt, {:error, error_type}}
        end
      end
    end
  end
end
