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
      &__MODULE__.handle_event/4,
      self()
    )

    {handler_id, ref}
  end

  @doc """
  Cleans up telemetry event capture.
  """
  def cleanup({handler_id, _ref}) do
    :telemetry.detach(handler_id)
  end

  @doc false
  def handle_event(event, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry_event, event, measurements, metadata})
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
    # Capture common telemetry span events (start, stop, exception)
    [
      [:axn, :start],
      [:axn, :stop],
      [:axn, :exception],
      [:test_app, :actions, :start],
      [:test_app, :actions, :stop],
      [:test_app, :actions, :exception],
      [:custom, :prefix, :start],
      [:custom, :prefix, :stop],
      [:custom, :prefix, :exception],
      [:my_app, :users, :start],
      [:my_app, :users, :stop],
      [:my_app, :users, :exception],
      [:my_app, :payments, :start],
      [:my_app, :payments, :stop],
      [:my_app, :payments, :exception]
    ]
  end

  defp events_to_capture(prefix) when is_list(prefix) do
    [
      prefix ++ [:start],
      prefix ++ [:stop],
      prefix ++ [:exception]
    ]
  end
end
