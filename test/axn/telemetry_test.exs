defmodule Axn.TelemetryTest do
  use ExUnit.Case
  alias Axn.TelemetryHelper

  # Test helper module for telemetry testing
  defmodule TestActions do
    use Axn, telemetry_prefix: [:test_app, :actions]

    action :successful_action do
      step :succeed_step

      def succeed_step(_ctx) do
        {:halt, {:ok, "success result"}}
      end
    end

    action :failing_action do
      step :fail_step

      def fail_step(_ctx) do
        {:halt, {:error, :some_error}}
      end
    end

    action :exception_action do
      step :raise_exception

      def raise_exception(_ctx) do
        raise RuntimeError, "Something went wrong"
      end
    end
  end

  # Test helper module with custom telemetry prefix
  defmodule CustomTelemetryActions do
    use Axn, telemetry_prefix: [:custom, :prefix]

    action :custom_action do
      step :handle_custom

      def handle_custom(_ctx) do
        {:halt, {:ok, "custom result"}}
      end
    end
  end

  # Test helper module without telemetry prefix (should use default)
  defmodule DefaultTelemetryActions do
    use Axn

    action :default_action do
      step :handle_default

      def handle_default(_ctx) do
        {:halt, {:ok, "default result"}}
      end
    end
  end

  setup do
    handler = TelemetryHelper.capture_events()
    on_exit(fn -> TelemetryHelper.cleanup(handler) end)
    {:ok, handler: handler}
  end

  describe "automatic telemetry span wrapping" do
    test "emits telemetry span for successful actions" do
      TestActions.run(:successful_action, %{}, %{})

      # Skip start event, get stop event which has the final result
      {:ok, {_start_event, _start_measurements, _start_metadata}} =
        TelemetryHelper.receive_event()

      {:ok, {event, measurements, metadata}} = TelemetryHelper.receive_event()

      assert event == [:test_app, :actions, :stop]
      assert is_integer(measurements[:duration])
      assert metadata[:action] == :successful_action
      assert metadata[:result_type] == :ok
    end

    test "emits telemetry span for failed actions" do
      TestActions.run(:failing_action, %{}, %{})

      # Skip start event, get stop event which has the final result
      {:ok, {_start_event, _start_measurements, _start_metadata}} =
        TelemetryHelper.receive_event()

      {:ok, {event, measurements, metadata}} = TelemetryHelper.receive_event()

      assert event == [:test_app, :actions, :stop]
      assert is_integer(measurements[:duration])
      assert metadata[:action] == :failing_action
      assert metadata[:result_type] == :error
    end

    test "emits telemetry span for exception actions" do
      # Exceptions should be converted to error tuples, not raised
      result = TestActions.run(:exception_action, %{}, %{})
      assert {:error, :step_exception} = result

      # For exceptions, we get start then exception event (no stop)
      {:ok, {_start_event, _start_measurements, _start_metadata}} =
        TelemetryHelper.receive_event()

      {:ok, {event, measurements, metadata}} = TelemetryHelper.receive_event()

      assert event == [:test_app, :actions, :exception]
      assert is_integer(measurements[:duration])
      assert metadata[:action] == :exception_action
      # Exception events show the initial state, not final error state
      assert metadata[:result_type] == :ok
    end
  end

  describe "configurable event naming" do
    test "uses telemetry_prefix from module configuration" do
      CustomTelemetryActions.run(:custom_action, %{}, %{})

      # Skip start event, get stop event
      {:ok, {_start_event, _start_measurements, _start_metadata}} =
        TelemetryHelper.receive_event()

      {:ok, {event, _measurements, metadata}} = TelemetryHelper.receive_event()

      assert event == [:custom, :prefix, :stop]
      assert metadata[:action] == :custom_action
    end

    test "uses default telemetry prefix when none provided" do
      DefaultTelemetryActions.run(:default_action, %{}, %{})

      # Skip start event, get stop event
      {:ok, {_start_event, _start_measurements, _start_metadata}} =
        TelemetryHelper.receive_event()

      {:ok, {event, _measurements, metadata}} = TelemetryHelper.receive_event()

      assert event == [:axn, :stop]
      assert metadata[:action] == :default_action
    end
  end

  describe "safe metadata extraction" do
    test "includes only safe metadata fields" do
      assigns = %{
        current_user: %{id: "user_123", password: "secret", email: "user@example.com"},
        secret_token: "super_secret"
      }

      params = %{"password" => "user_password", "credit_card" => "4111111111111111"}

      TestActions.run(:successful_action, assigns, params)

      # Skip start event, get stop event with final metadata
      {:ok, {_start_event, _start_measurements, _start_metadata}} =
        TelemetryHelper.receive_event()

      {:ok, {_event, _measurements, metadata}} = TelemetryHelper.receive_event()

      # Only these safe fields should be present (plus telemetry internal fields)
      expected_keys = [:action, :result_type, :user_id, :telemetry_span_context]
      actual_keys = Map.keys(metadata) |> Enum.sort()
      assert actual_keys == Enum.sort(expected_keys)

      # Verify safe values
      assert metadata[:action] == :successful_action
      assert metadata[:result_type] == :ok
      assert metadata[:user_id] == "user_123"
    end

    test "user_id is nil when current_user is not present" do
      TestActions.run(:successful_action, %{}, %{})

      # Skip start event, get stop event
      {:ok, {_start_event, _start_measurements, _start_metadata}} =
        TelemetryHelper.receive_event()

      {:ok, {_event, _measurements, metadata}} = TelemetryHelper.receive_event()
      assert metadata[:user_id] == nil
    end

    test "user_id is nil when current_user has no id" do
      assigns = %{current_user: %{name: "John"}}
      TestActions.run(:successful_action, assigns, %{})

      # Skip start event, get stop event
      {:ok, {_start_event, _start_measurements, _start_metadata}} =
        TelemetryHelper.receive_event()

      {:ok, {_event, _measurements, metadata}} = TelemetryHelper.receive_event()
      assert metadata[:user_id] == nil
    end
  end

  describe "telemetry reliability" do
    test "telemetry works when no handlers are attached" do
      # Should not crash when no handlers are attached
      assert {:ok, "success result"} = TestActions.run(:successful_action, %{}, %{})
      assert {:error, :some_error} = TestActions.run(:failing_action, %{}, %{})
    end
  end
end
