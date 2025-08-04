defmodule Axn do
  @moduledoc """
  Axn - A clean, step-based DSL library for defining actions with parameter validation,
  authorization, telemetry, and custom business logic.
  """

  alias Axn.Steps.CastValidateParams

  @doc """
  Sets up a module to use the Axn DSL for defining actions.

  ## Options

  * `:metadata` - Function that takes a context and returns a map of custom metadata
    for telemetry events. Optional.

  ## Examples

      defmodule MyApp.UserActions do
        use Axn

        action :create_user do
          # Action definition
        end
      end

      defmodule MyApp.UserActions do
        use Axn, metadata: &__MODULE__.telemetry_metadata/1

        def telemetry_metadata(ctx) do
          %{
            user_id: ctx.assigns.current_user && ctx.assigns.current_user.id,
            tenant: ctx.assigns.tenant && ctx.assigns.tenant.slug
          }
        end
      end
  """
  defmacro __using__(opts) do
    metadata_fn = Keyword.get(opts, :metadata)

    quote do
      import Axn, only: [action: 2, action: 3, step: 1, step: 2]
      import Axn.Context

      alias Axn.Context

      @telemetry_metadata_fn unquote(metadata_fn)
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

      action :create_user, metadata: &action_metadata/1 do
        step :cast_validate_params, schema: %{name!: :string}
        step :handle_create
      end
  """
  defmacro action(name, do: block) do
    quote do
      @current_action unquote(name)
      @steps []

      unquote(block)

      @actions [{unquote(name), Enum.reverse(@steps), []} | @actions]
      @current_action nil
      @steps []
    end
  end

  @doc """
  Defines an action with options and its steps.

  ## Options

  * `:metadata` - Function that takes a context and returns a map of action-specific metadata
    for telemetry events. Optional.

  ## Examples

      action :create_user, metadata: &create_user_metadata/1 do
        step :cast_validate_params, schema: %{name!: :string}
        step :handle_create
      end
  """
  defmacro action(name, opts, do: block) do
    quote do
      @current_action unquote(name)
      @steps []

      unquote(block)

      @actions [{unquote(name), Enum.reverse(@steps), unquote(opts)} | @actions]
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
      Runs an action with the given parameters and source.

      The source can be:
      - A plain map (treated as assigns)
      - A struct with an assigns field (e.g., Phoenix.Socket, Plug.Conn)
      - Any other struct/map (treated as assigns)

      Returns `{:ok, result}` on success or `{:error, reason}` on failure.

      ## Examples

          # With plain assigns map
          run(:create_user, %{"name" => "John"}, %{current_user: user})

          # With Phoenix LiveView socket
          run(:create_user, %{"name" => "John"}, socket)

          # With Plug connection
          run(:create_user, %{"name" => "John"}, conn)
      """
      def run(action, params, source) do
        case run_action_pipeline(action, params, source) do
          %Axn.Context{result: result} -> normalize_result(result)
          {:error, reason} -> {:error, reason}
        end
      end

      defp extract_assigns_and_source(source) do
        case source do
          %{assigns: assigns} -> {assigns, source}
          assigns when is_map(assigns) -> {assigns, source}
          _ -> {%{}, source}
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
        case Enum.find(@actions, fn {name, _steps, _opts} -> name == action_name end) do
          {_name, steps, opts} -> {:ok, steps, opts}
          nil -> {:error, :action_not_found}
        end
      end
    end
  end

  defp generate_pipeline_functions do
    quote do
      defp run_action_pipeline(action, params, source) do
        case find_action(action) do
          {:ok, steps, action_opts} ->
            {assigns, original_source} = extract_assigns_and_source(source)

            ctx = %Axn.Context{
              action: action,
              assigns: assigns,
              params: params,
              private: %{source: original_source}
            }

            run_action_with_telemetry(ctx, steps, action_opts)

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
      defp run_action_with_telemetry(%Axn.Context{} = ctx, steps, action_opts) do
        metadata = build_telemetry_metadata(ctx, action_opts)

        try do
          :telemetry.span(
            [:axn, :action],
            metadata,
            fn ->
              result_ctx = run_step_pipeline(steps, ctx)
              final_metadata = build_telemetry_metadata(result_ctx, action_opts)
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

      defp build_telemetry_metadata(%Axn.Context{} = ctx, action_opts) do
        # Always include module and action for filtering/debugging
        %{module: __MODULE__, action: ctx.action}
        |> Map.merge(get_module_metadata(ctx))
        |> Map.merge(get_action_metadata(ctx, action_opts))
      end

      defp get_action_metadata(ctx, action_opts) do
        action_opts
        |> Keyword.get(:metadata)
        |> safe_call_metadata_fn(ctx)
      end

      defp get_module_metadata(ctx) do
        safe_call_metadata_fn(@telemetry_metadata_fn, ctx)
      end

      defp safe_call_metadata_fn(metadata_fn, ctx) when is_function(metadata_fn) do
        metadata_fn.(ctx) || %{}
      rescue
        _ -> %{}
      end

      defp safe_call_metadata_fn(_metadata_fn, _ctx) do
        %{}
      end
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
