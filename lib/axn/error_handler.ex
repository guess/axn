defmodule Axn.ErrorHandler do
  @moduledoc """
  Handles error sanitization and exception conversion for Axn actions.

  This module provides utilities to:
  - Convert exceptions to standardized error tuples
  - Create safe error messages for logging and telemetry
  - Basic sanitization for common sensitive data patterns
  """

  @doc """
  Sanitizes an error map by creating safe messages.
  """
  def sanitize_error(error) when is_map(error) do
    add_safe_message(error)
  end

  def sanitize_error(error), do: error

  @doc """
  Converts an exception to a standardized error tuple.
  """
  def exception_to_error(exception, step, action, context \\ nil) do
    %{
      reason: :step_exception,
      step: step,
      action: action,
      exception_type: exception.__struct__,
      safe_message: create_safe_exception_message(exception),
      context_snapshot: sanitize_context(context)
    }
  end

  # Private functions

  defp add_safe_message(error) when is_map(error) do
    safe_message =
      case error.reason do
        :validation_failed -> "Validation failed for provided data"
        :database_error -> "Database operation failed - data may already exist"
        :api_error -> "External service error occurred"
        :payment_gateway_error -> "Payment processing error occurred"
        :step_exception -> "An error occurred during processing"
        _ -> "An error occurred"
      end

    Map.put(error, :safe_message, safe_message)
  end

  defp create_safe_exception_message(exception) do
    case exception.__struct__ do
      ArgumentError -> "Invalid argument provided to service"
      RuntimeError -> "Service error occurred during processing"
      File.Error -> "File system error occurred"
      _ -> "An unexpected error occurred during processing"
    end
  end

  defp sanitize_context(nil), do: nil

  defp sanitize_context(%Axn.Context{} = ctx) do
    %{
      action: ctx.action,
      params: ctx.params,
      assigns: sanitize_assigns(ctx.assigns)
    }
  end

  defp sanitize_context(_), do: nil

  defp sanitize_assigns(assigns) when is_map(assigns) do
    assigns
    |> Map.drop([:current_user])
    |> Map.put(:user_id, get_user_id(assigns))
  end

  defp get_user_id(%{current_user: %{id: id}}), do: id
  defp get_user_id(_), do: nil

  @doc """
  Basic changeset sanitization.
  """
  def sanitize_changeset(%Ecto.Changeset{} = changeset) do
    changeset
  end

  def sanitize_changeset(changeset), do: changeset
end
