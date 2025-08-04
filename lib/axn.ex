defmodule Axn do
  @moduledoc """
  Axn - A clean, step-based DSL library for defining actions with parameter validation,
  authorization, telemetry, and custom business logic.

  Axn provides a unified interface that works seamlessly across Phoenix Controllers 
  and LiveViews, solving the limitation that Plugs only work with `Plug.Conn`.

  ## Core Features

  * **Step-based Pipeline**: Define actions as a series of composable steps that execute in order
  * **Parameter Validation**: Built-in schema-based parameter casting and validation using `Params`
  * **Authorization**: Simple patterns for implementing custom authorization logic
  * **Telemetry**: Automatic telemetry events with configurable metadata for monitoring
  * **Phoenix Integration**: Works with both Controllers (Plug.Conn) and LiveViews (Phoenix.Socket)
  * **Error Handling**: Consistent, structured error formats across all operations
  * **Composability**: Steps can be reused across actions and even shared between modules

  ## Key Concepts

  ### Actions
  Actions are named units of work that execute a series of steps in order. Each action 
  automatically gets telemetry wrapping and error handling.

  ### Steps  
  Steps are individual functions that take a context and either continue the pipeline 
  or halt it. Steps follow a simple contract: `(ctx, opts) -> {:cont, new_ctx} | {:halt, result}`.

  ### Context
  An `Axn.Context` struct flows through the step pipeline, carrying request data, user 
  information, and any step-added fields. Provides helper functions similar to `Plug.Conn` 
  and `Phoenix.Component`.

  ## Quick Example

      defmodule MyApp.UserActions do
        use Axn
        
        action :create_user do
          step :cast_validate_params, schema: %{email!: :string, name!: :string}
          step :require_admin
          step :handle_create
        end
        
        def require_admin(ctx) do
          if admin?(ctx.assigns.current_user) do
            {:cont, ctx}
          else
            {:halt, {:error, :unauthorized}}
          end
        end
        
        def handle_create(ctx) do
          case Users.create(ctx.params) do
            {:ok, user} -> {:halt, {:ok, user}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end
        
        defp admin?(user), do: user && user.role == "admin"
      end

  ## Usage in Phoenix

      # Phoenix Controller
      def create(conn, params) do
        case MyApp.UserActions.run(:create_user, params, conn) do
          {:ok, user} -> json(conn, %{success: true, user: user})
          {:error, %{reason: :invalid_params, changeset: changeset}} ->
            json(conn, %{errors: format_changeset_errors(changeset)})
          {:error, reason} -> json(conn, %{error: reason})
        end
      end

      # Phoenix LiveView  
      def handle_event("submit", params, socket) do
        case MyApp.UserActions.run(:create_user, params, socket) do
          {:ok, user} -> {:noreply, assign(socket, :user, user)}
          {:error, reason} -> {:noreply, put_flash(socket, :error, reason)}
        end
      end

  ## Design Principles

  * **Explicit over implicit**: Each action clearly shows its execution flow
  * **Composable**: Steps should be reusable across actions and modules  
  * **Safe by default**: Telemetry and error handling do not leak sensitive data
  * **Simple to implement**: Minimal macro magic, straightforward execution model
  * **Easy to test**: Steps are pure functions that are easy to unit test
  * **Familiar patterns**: Feels natural to experienced Elixir developers

  See the module documentation for `Axn.Context` for details on the context struct
  and helper functions available in steps.
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

  Steps must implement one of these function signatures:
  * `step_name(ctx)` - Receives context only
  * `step_name(ctx, opts)` - Receives context and step options

  ## Return Values

  Steps must return one of:
  * `{:cont, updated_context}` - Continue to next step with updated context
  * `{:halt, {:ok, result}}` - Stop pipeline with success result
  * `{:halt, {:error, reason}}` - Stop pipeline with error result

  ## Examples

      # Step with no options
      step :my_step
      
      # Step with options  
      step :my_step, option: value
      
      # External step from another module
      step {ExternalModule, :external_step}, option: value
      
      # Built-in parameter validation step
      step :cast_validate_params, schema: %{name!: :string, age: :integer}

  ## Step Implementation

      # Simple step that just continues
      def my_step(ctx) do
        {:cont, Context.assign(ctx, :processed, true)}
      end
      
      # Step with options that modifies context
      def my_step_with_options(ctx, opts) do
        value = Keyword.get(opts, :option, "default")
        {:cont, Context.assign(ctx, :custom_value, value)}
      end
      
      # Step that can halt the pipeline
      def require_admin(ctx) do
        if admin?(ctx.assigns.current_user) do
          {:cont, ctx}
        else
          {:halt, {:error, :unauthorized}}
        end
      end
      
      # Step that completes the action
      def handle_create(ctx) do
        case create_user(ctx.params) do
          {:ok, user} -> {:halt, {:ok, user}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end
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

      This is the primary entry point for executing actions. It handles the full
      action pipeline including parameter processing, step execution, telemetry,
      and error handling.

      ## Parameters

      * `action` - Atom representing the action name to execute
      * `params` - Map of parameters to pass to the action (typically user input)
      * `source` - Context source containing assigns and other request data

      ## Source Types

      The source parameter provides context and can be:
      * **Plain map** - Treated as assigns directly
      * **Phoenix.LiveView.Socket** - Assigns extracted from `socket.assigns`
      * **Plug.Conn** - Assigns extracted from `conn.assigns`
      * **Any struct with `assigns` field** - Assigns extracted automatically

      The original source is preserved in `ctx.private.source` for steps that need
      to access framework-specific functionality.

      ## Return Values

      * `{:ok, result}` - Action completed successfully
      * `{:error, reason}` - Action failed, see error formats below

      ## Error Formats

      Different types of failures return structured error information:

      ### Action/Step Resolution Errors
      * `{:error, :action_not_found}` - The specified action doesn't exist
      * `{:error, :step_not_found}` - A step function couldn't be found
      ### Parameter Validation Errors
      * `{:error, %{reason: :invalid_params, changeset: changeset}}` - Parameter validation failed
        
        The changeset contains field-level validation errors and can be used to
        generate user-friendly error messages.

      ### Step Execution Errors
      * `{:error, %{reason: :step_exception, message: message, step: step_name}}` - Step raised an exception
      * `{:error, custom_reason}` - Custom error returned by a step via `{:halt, {:error, custom_reason}}`

      ### Authorization Errors
      * `{:error, :unauthorized}` - Standard format for authorization failures
      * `{:error, :forbidden}` - Alternative format for permission denied

      ## Framework Integration Examples

      ### Phoenix Controller Usage
          def create(conn, params) do
            case MyApp.UserActions.run(:create_user, params, conn) do
              {:ok, user} -> 
                json(conn, %{success: true, user: user})
              {:error, %{reason: :invalid_params, changeset: changeset}} ->
                conn
                |> put_status(400)
                |> json(%{errors: format_changeset_errors(changeset)})
              {:error, :unauthorized} ->
                conn
                |> put_status(403)
                |> json(%{error: "Unauthorized"})
              {:error, reason} ->
                conn
                |> put_status(500)
                |> json(%{error: "Internal error"})
            end
          end

      ### Phoenix LiveView Usage
          def handle_event("submit", params, socket) do
            case MyApp.FormActions.run(:submit_form, params, socket) do
              {:ok, result} -> 
                {:noreply, socket |> put_flash(:info, "Success!") |> assign(:result, result)}
              {:error, %{reason: :invalid_params, changeset: changeset}} ->
                {:noreply, assign(socket, :changeset, changeset)}
              {:error, reason} -> 
                {:noreply, put_flash(socket, :error, "Error: \#{inspect(reason)}")}
            end
          end

      ### Direct Usage with Assigns Map
          assigns = %{current_user: user, tenant: tenant}
          case MyApp.BusinessActions.run(:process_order, order_params, assigns) do
            {:ok, order} -> {:ok, order}
            {:error, reason} -> handle_error(reason)
          end

      ## Telemetry Events

      All action executions automatically emit telemetry events:
      * `[:axn, :action, :start]` - When action begins
      * `[:axn, :action, :stop]` - When action completes successfully  
      * `[:axn, :action, :exception]` - When action fails with exception

      Events include metadata such as module, action name, duration, and any
      custom metadata configured via `:metadata` options.
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
      # Wraps action execution with telemetry events.
      #
      # Emits :telemetry.span/3 events with the following structure:
      # - Event name: [:axn, :action]
      # - Start metadata: %{module: __MODULE__, action: action_name, ...custom...}  
      # - Stop metadata: Same as start, plus any context changes during execution
      # - Exception metadata: Same as start, plus exception details
      #
      # Custom metadata functions are called safely and default to %{} on error.
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

      # Builds telemetry metadata by merging default, module-level, and action-level metadata.
      #
      # Metadata precedence (later metadata overwrites earlier on key conflicts):
      # 1. Default metadata: %{module: __MODULE__, action: ctx.action}
      # 2. Module-level metadata: Configured via `use Axn, metadata: &function/1`
      # 3. Action-level metadata: Configured via `action :name, metadata: &function/1`
      #
      # All custom metadata functions are called safely and return %{} on error.
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

      # Safely calls a metadata function, returning %{} on any error.
      #
      # This ensures that telemetry never fails due to custom metadata functions
      # and provides a consistent fallback behavior.
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
