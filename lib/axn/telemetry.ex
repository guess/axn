defmodule Axn.Telemetry do
  @moduledoc """
  Telemetry integration for Axn actions.

  This module handles automatic telemetry event emission for action execution,
  including custom metadata collection and safe error handling.
  """

  alias Axn.Context

  @doc """
  Wraps step execution with telemetry events.

  Emits `:telemetry.span/3` events with the following structure:
  * Event name: `[:axn, :action]`
  * Start metadata: Default + module + action metadata
  * Stop metadata: Same as start, plus any context changes during execution
  * Exception metadata: Same as start, plus exception details

  Custom metadata functions are called safely and default to `%{}` on error.

  ## Parameters

  * `ctx` - Initial Context struct
  * `action_opts` - Action-level options (may include `:metadata` function)
  * `module_opts` - Module-level options (may include `:metadata` function)
  * `runner` - The function to run the action

  ## Return Value

  Returns a Context struct with the final execution state and result.
  """
  def run_with_telemetry(%Context{} = ctx, action_opts, module_opts, runner) do
    metadata = build_metadata(ctx, action_opts, module_opts)

    try do
      :telemetry.span(
        [:axn, :action],
        metadata,
        fn ->
          result_ctx = runner.()
          final_metadata = build_metadata(result_ctx, action_opts, module_opts)
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

  @doc """
  Builds telemetry metadata by merging default, module-level, and action-level metadata.

  Metadata precedence (later metadata overwrites earlier on key conflicts):
  1. Default metadata: `%{module: ctx.module, action: ctx.action}`
  2. Module-level metadata: Configured via `use Axn, metadata: &function/1`
  3. Action-level metadata: Configured via `action :name, metadata: &function/1`

  All custom metadata functions are called safely and return `%{}` on error.

  ## Parameters

  * `ctx` - Context struct containing action information
  * `action_opts` - Action-level options (may include `:metadata` function)
  * `module_opts` - Module-level options (may include `:metadata` function)

  ## Return Value

  Returns a map of telemetry metadata.
  """
  def build_metadata(%Context{} = ctx, action_opts, module_opts) do
    # Always include module and action for filtering/debugging
    %{module: ctx.module, action: ctx.action}
    |> Map.merge(get_metadata(ctx, module_opts))
    |> Map.merge(get_metadata(ctx, action_opts))
  end

  @doc """
  Extracts metadata from options.

  Looks for the `:metadata` key in options and safely calls the function
  if present. Returns empty map if no metadata function or on error.
  """
  def get_metadata(ctx, opts) do
    opts
    |> Keyword.get(:metadata)
    |> safe_call_metadata_fn(ctx)
  end

  # Safely calls a metadata function, returning `%{}` on any error.
  defp safe_call_metadata_fn(metadata_fn, ctx) when is_function(metadata_fn) do
    metadata_fn.(ctx) || %{}
  rescue
    _ -> %{}
  end

  defp safe_call_metadata_fn(_metadata_fn, _ctx) do
    %{}
  end
end
