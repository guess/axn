defmodule Axn.TelemetryHelper do
  @moduledoc """
  Simple helper for capturing telemetry events in tests.
  """

  @doc """
  Captures all telemetry events with the given prefix.
  Returns a reference that can be used for cleanup.
  """
  def capture_events(prefix \\ []) do
    ref = make_ref()
    handler_id = "test-handler-#{inspect(ref)}"
    
    :telemetry.attach_many(
      handler_id,
      events_to_capture(prefix),
      fn event, measurements, metadata, _acc ->
        send(self(), {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )
    
    {handler_id, ref}
  end

  @doc """
  Cleans up telemetry event capture.
  """
  def cleanup({handler_id, _ref}) do
    :telemetry.detach(handler_id)
  end

  @doc """
  Receives the next telemetry event, with optional timeout.
  """
  def receive_event(timeout \\ 100) do
    receive do
      {:telemetry_event, event, measurements, metadata} ->
        {:ok, {event, measurements, metadata}}
    after
      timeout -> :timeout
    end
  end

  @doc """
  Receives all telemetry events matching a prefix within timeout.
  """
  def receive_matching_events(prefix, timeout \\ 100) do
    receive_matching_events(prefix, [], timeout)
  end

  defp receive_matching_events(prefix, acc, timeout) do
    case receive_event(timeout) do
      {:ok, {event, measurements, metadata}} ->
        if List.starts_with?(event, prefix) do
          receive_matching_events(prefix, [{event, measurements, metadata} | acc], timeout)
        else
          receive_matching_events(prefix, acc, timeout)
        end
      :timeout ->
        Enum.reverse(acc)
    end
  end

  # Private helper to determine which events to capture
  defp events_to_capture([]) do
    # Capture common telemetry events when no prefix specified
    [
      [:axn],
      [:test_app, :actions],
      [:custom, :prefix, :events]
    ]
  end

  defp events_to_capture(prefix) when is_list(prefix) do
    [prefix]
  end
end