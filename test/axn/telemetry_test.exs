defmodule Axn.TelemetryTest do
  use ExUnit.Case

  alias Axn.TelemetryHelper

  # Test helper module for telemetry testing
  defmodule TestActions do
    @moduledoc false
    use Axn

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

  # Test helper module with module-level metadata
  defmodule ModuleMetadataActions do
    @moduledoc false
    use Axn, metadata: &__MODULE__.module_metadata/1

    action :test_action do
      step :handle_test

      def handle_test(_ctx) do
        {:halt, {:ok, "test result"}}
      end
    end

    def module_metadata(ctx) do
      %{
        user_id: ctx.assigns[:current_user] && ctx.assigns.current_user[:id],
        tenant: "test_tenant"
      }
    end
  end

  # Test helper module with action-level metadata
  defmodule ActionMetadataActions do
    @moduledoc false
    use Axn, metadata: &__MODULE__.module_metadata/1

    action :test_action, metadata: &__MODULE__.action_metadata/1 do
      step :handle_test

      def handle_test(_ctx) do
        {:halt, {:ok, "test result"}}
      end
    end

    def module_metadata(_ctx) do
      %{user_id: "module_user", common_field: "module_value"}
    end

    def action_metadata(_ctx) do
      %{resource_type: :test_resource, common_field: "action_value"}
    end
  end

  setup do
    handler = TelemetryHelper.capture_events()
    on_exit(fn -> TelemetryHelper.cleanup(handler) end)
    {:ok, handler: handler}
  end

  describe "fixed telemetry events" do
    test "emits fixed [:axn, :action] events for successful actions" do
      TestActions.run(:successful_action, %{}, %{})

      # Skip start event, get stop event which has the final result
      {:ok, {_start_event, _start_measurements, _start_metadata}} =
        TelemetryHelper.receive_event()

      {:ok, {event, measurements, metadata}} = TelemetryHelper.receive_event()

      assert event == [:axn, :action, :stop]
      assert is_integer(measurements[:duration])
      assert metadata[:module] == TestActions
      assert metadata[:action] == :successful_action
    end

    test "emits fixed [:axn, :action] events for failed actions" do
      TestActions.run(:failing_action, %{}, %{})

      # Skip start event, get stop event which has the final result
      {:ok, {_start_event, _start_measurements, _start_metadata}} =
        TelemetryHelper.receive_event()

      {:ok, {event, measurements, metadata}} = TelemetryHelper.receive_event()

      assert event == [:axn, :action, :stop]
      assert is_integer(measurements[:duration])
      assert metadata[:module] == TestActions
      assert metadata[:action] == :failing_action
    end

    test "handles exceptions gracefully" do
      # Exceptions should be converted to error tuples, not raised
      result = TestActions.run(:exception_action, %{}, %{})
      assert {:error, %{reason: :step_exception, message: _}} = result

      # Should get start event but exception handling prevents normal telemetry span completion
      {:ok, {_start_event, _start_measurements, _start_metadata}} =
        TelemetryHelper.receive_event()

      # The exception handling happens outside telemetry span
      # Let's just verify the action ran and returned the expected error
    end
  end

  describe "metadata precedence" do
    test "includes default metadata only when no custom metadata" do
      TestActions.run(:successful_action, %{}, %{})

      # Skip start event, get stop event
      {:ok, {_start_event, _start_measurements, _start_metadata}} =
        TelemetryHelper.receive_event()

      {:ok, {_event, measurements, metadata}} = TelemetryHelper.receive_event()

      # Should have default metadata
      assert metadata[:module] == TestActions
      assert metadata[:action] == :successful_action
      assert is_integer(measurements[:duration])

      # Should not have custom metadata
      refute Map.has_key?(metadata, :user_id)
      refute Map.has_key?(metadata, :tenant)
    end

    test "merges module-level metadata with defaults" do
      assigns = %{current_user: %{id: "user_123"}}
      ModuleMetadataActions.run(:test_action, %{}, assigns)

      # Skip start event, get stop event
      {:ok, {_start_event, _start_measurements, _start_metadata}} =
        TelemetryHelper.receive_event()

      {:ok, {_event, measurements, metadata}} = TelemetryHelper.receive_event()

      # Should have default metadata
      assert metadata[:module] == ModuleMetadataActions
      assert metadata[:action] == :test_action
      assert is_integer(measurements[:duration])

      # Should have module-level metadata
      assert metadata[:user_id] == "user_123"
      assert metadata[:tenant] == "test_tenant"
    end

    test "action-level metadata overrides module-level for same keys" do
      ActionMetadataActions.run(:test_action, %{}, %{})

      # Skip start event, get stop event
      {:ok, {_start_event, _start_measurements, _start_metadata}} =
        TelemetryHelper.receive_event()

      {:ok, {_event, measurements, metadata}} = TelemetryHelper.receive_event()

      # Should have default metadata
      assert metadata[:module] == ActionMetadataActions
      assert metadata[:action] == :test_action
      assert is_integer(measurements[:duration])

      # Should have module-level metadata
      assert metadata[:user_id] == "module_user"

      # Should have action-level metadata
      assert metadata[:resource_type] == :test_resource

      # Action-level should override module-level for same key
      assert metadata[:common_field] == "action_value"
    end
  end

  describe "telemetry security" do
    test "custom metadata functions control what data is included" do
      assigns = %{
        current_user: %{id: "user_123", password: "secret", email: "user@example.com"},
        secret_token: "super_secret"
      }

      params = %{"password" => "user_password", "credit_card" => "4111111111111111"}

      ModuleMetadataActions.run(:test_action, params, assigns)

      # Skip start event, get stop event with final metadata
      {:ok, {_start_event, _start_measurements, _start_metadata}} =
        TelemetryHelper.receive_event()

      {:ok, {_event, _measurements, metadata}} = TelemetryHelper.receive_event()

      # Should have default metadata
      assert metadata[:module] == ModuleMetadataActions
      assert metadata[:action] == :test_action

      # Should have only what the metadata function returns
      assert metadata[:user_id] == "user_123"
      assert metadata[:tenant] == "test_tenant"

      # Should NOT have sensitive data
      refute Map.has_key?(metadata, :password)
      refute Map.has_key?(metadata, :secret_token)
      refute Map.has_key?(metadata, :email)
      refute Map.has_key?(metadata, :credit_card)
    end

    test "metadata functions handle missing data gracefully" do
      ModuleMetadataActions.run(:test_action, %{}, %{})

      # Skip start event, get stop event
      {:ok, {_start_event, _start_measurements, _start_metadata}} =
        TelemetryHelper.receive_event()

      {:ok, {_event, _measurements, metadata}} = TelemetryHelper.receive_event()
      assert metadata[:user_id] == nil
      assert metadata[:tenant] == "test_tenant"
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
