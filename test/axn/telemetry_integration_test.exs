defmodule Axn.TelemetryIntegrationTest do
  use ExUnit.Case
  alias Axn.TelemetryHelper

  @moduledoc """
  Integration tests for telemetry functionality using realistic action patterns.
  Tests telemetry behavior with complex multi-step actions, parameter validation,
  authorization, and business logic flows.
  """

  # Realistic user action module with typical patterns
  defmodule UserActions do
    use Axn, telemetry_prefix: [:my_app, :users]

    action :create_user do
      step :cast_validate_params,
        schema: %{email!: :string, name!: :string, role: [field: :string, default: "user"]}

      step :authorize_user_creation
      step :check_email_uniqueness
      step :create_user_record
      step :send_welcome_email

      def authorize_user_creation(ctx) do
        current_user = ctx.assigns[:current_user]

        if current_user && current_user.role == "admin" do
          {:cont, ctx}
        else
          {:halt, {:error, :unauthorized}}
        end
      end

      def check_email_uniqueness(ctx) do
        # Simulate database check
        if ctx.params.email == "duplicate@example.com" do
          {:halt, {:error, %{reason: :email_taken, email: ctx.params.email}}}
        else
          {:cont, ctx}
        end
      end

      def create_user_record(ctx) do
        # Simulate user creation
        user = %{
          id: "user_#{:rand.uniform(1000)}",
          email: ctx.params.email,
          name: ctx.params.name,
          role: ctx.params.role
        }

        {:cont, ctx |> put_private(:created_user, user)}
      end

      def send_welcome_email(ctx) do
        user = get_private(ctx, :created_user)
        # Simulate email sending
        {:halt, {:ok, %{user: user, message: "User created and welcome email sent"}}}
      end
    end

    action :update_user_profile do
      step :cast_validate_params, schema: %{user_id!: :string, name: :string, bio: :string}
      step :load_user
      step :authorize_profile_update
      step :update_profile
      step :log_profile_change

      def load_user(ctx) do
        # Simulate loading user
        if ctx.params.user_id == "nonexistent" do
          {:halt, {:error, :user_not_found}}
        else
          user = %{id: ctx.params.user_id, name: "Original Name", bio: "Original bio"}
          {:cont, ctx |> put_private(:user, user)}
        end
      end

      def authorize_profile_update(ctx) do
        current_user = ctx.assigns[:current_user]
        user = get_private(ctx, :user)

        if current_user && (current_user.id == user.id || current_user.role == "admin") do
          {:cont, ctx}
        else
          {:halt, {:error, :forbidden}}
        end
      end

      def update_profile(ctx) do
        user = get_private(ctx, :user)
        updates = Map.take(ctx.params, [:name, :bio])
        updated_user = Map.merge(user, updates)
        {:cont, ctx |> put_private(:updated_user, updated_user)}
      end

      def log_profile_change(ctx) do
        updated_user = get_private(ctx, :updated_user)
        {:halt, {:ok, %{user: updated_user, message: "Profile updated successfully"}}}
      end
    end

    action :complex_failing_action do
      step :step1
      step :step2
      step :failing_step
      step :step4

      def step1(ctx), do: {:cont, ctx |> put_private(:step1_done, true)}
      def step2(ctx), do: {:cont, ctx |> put_private(:step2_done, true)}
      def failing_step(_ctx), do: raise("Complex failure in step 3")
      def step4(ctx), do: {:cont, ctx |> put_result("never reached")}
    end
  end

  # Another realistic module with different telemetry prefix
  defmodule PaymentActions do
    use Axn, telemetry_prefix: [:my_app, :payments]

    action :process_payment do
      step :cast_validate_params,
        schema: %{amount!: :integer, currency: [field: :string, default: "USD"]}

      step :validate_amount
      step :charge_payment
      step :record_transaction

      def validate_amount(ctx) do
        if ctx.params.amount <= 0 do
          {:halt, {:error, %{reason: :invalid_amount, amount: ctx.params.amount}}}
        else
          {:cont, ctx}
        end
      end

      def charge_payment(ctx) do
        # Simulate payment processing
        if ctx.params.amount > 10000 do
          {:halt, {:error, %{reason: :amount_too_large, limit: 10000}}}
        else
          transaction_id = "txn_#{:rand.uniform(100_000)}"
          {:cont, ctx |> put_private(:transaction_id, transaction_id)}
        end
      end

      def record_transaction(ctx) do
        transaction_id = get_private(ctx, :transaction_id)

        result = %{
          transaction_id: transaction_id,
          amount: ctx.params.amount,
          currency: ctx.params.currency,
          status: "completed"
        }

        {:halt, {:ok, result}}
      end
    end
  end

  setup do
    handler = TelemetryHelper.capture_events()
    on_exit(fn -> TelemetryHelper.cleanup(handler) end)
    {:ok, handler: handler}
  end

  describe "multi-step action telemetry" do
    test "successful multi-step action emits correct telemetry" do
      admin_user = %{id: "admin_123", role: "admin"}
      assigns = %{current_user: admin_user}
      params = %{"email" => "test@example.com", "name" => "Test User"}

      result = UserActions.run(:create_user, assigns, params)
      assert {:ok, %{user: user, message: _}} = result
      assert user.email == "test@example.com"

      # Should get start and stop events
      {:ok, {start_event, start_measurements, start_metadata}} = TelemetryHelper.receive_event()
      {:ok, {stop_event, stop_measurements, stop_metadata}} = TelemetryHelper.receive_event()

      # Verify event names match telemetry prefix
      assert start_event == [:my_app, :users, :start]
      assert stop_event == [:my_app, :users, :stop]

      # Verify measurements include duration
      assert is_integer(start_measurements[:monotonic_time])
      assert is_integer(stop_measurements[:duration])

      # Verify metadata includes safe fields
      assert start_metadata[:action] == :create_user
      assert start_metadata[:user_id] == "admin_123"
      assert start_metadata[:result_type] == :ok

      assert stop_metadata[:action] == :create_user
      assert stop_metadata[:user_id] == "admin_123"
      assert stop_metadata[:result_type] == :ok
    end

    test "action with business logic failure emits error telemetry" do
      admin_user = %{id: "admin_123", role: "admin"}
      assigns = %{current_user: admin_user}
      params = %{"email" => "duplicate@example.com", "name" => "Test User"}

      result = UserActions.run(:create_user, assigns, params)
      assert {:error, %{reason: :email_taken, email: "duplicate@example.com"}} = result

      # Skip start event, get stop event
      {:ok, {_start_event, _start_measurements, _start_metadata}} =
        TelemetryHelper.receive_event()

      {:ok, {stop_event, _stop_measurements, stop_metadata}} = TelemetryHelper.receive_event()

      assert stop_event == [:my_app, :users, :stop]
      assert stop_metadata[:action] == :create_user
      assert stop_metadata[:result_type] == :error
    end

    test "authorization failure emits error telemetry" do
      regular_user = %{id: "user_123", role: "user"}
      assigns = %{current_user: regular_user}
      params = %{"email" => "test@example.com", "name" => "Test User"}

      result = UserActions.run(:create_user, assigns, params)
      assert {:error, :unauthorized} = result

      # Skip start event, get stop event
      {:ok, {_start_event, _start_measurements, _start_metadata}} =
        TelemetryHelper.receive_event()

      {:ok, {stop_event, _stop_measurements, stop_metadata}} = TelemetryHelper.receive_event()

      assert stop_event == [:my_app, :users, :stop]
      assert stop_metadata[:result_type] == :error
    end

    test "exception in complex action emits exception telemetry" do
      admin_user = %{id: "admin_123", role: "admin"}
      assigns = %{current_user: admin_user}

      result = UserActions.run(:complex_failing_action, assigns, %{})
      assert {:error, %{reason: :step_exception, message: "Complex failure in step 3"}} = result

      # Should get start and exception events (no stop for exceptions)
      {:ok, {start_event, _start_measurements, start_metadata}} = TelemetryHelper.receive_event()

      {:ok, {exception_event, _exception_measurements, exception_metadata}} =
        TelemetryHelper.receive_event()

      assert start_event == [:my_app, :users, :start]
      assert exception_event == [:my_app, :users, :exception]

      assert start_metadata[:action] == :complex_failing_action
      assert exception_metadata[:action] == :complex_failing_action
    end
  end

  describe "different telemetry prefixes" do
    test "different modules use their own telemetry prefixes" do
      # Test UserActions with [:my_app, :users] prefix
      admin_user = %{id: "admin_123", role: "admin"}
      params = %{"user_id" => "user_123", "name" => "Updated Name"}

      UserActions.run(:update_user_profile, %{current_user: admin_user}, params)

      {:ok, {user_start_event, _, _}} = TelemetryHelper.receive_event()
      {:ok, {user_stop_event, _, _}} = TelemetryHelper.receive_event()

      assert user_start_event == [:my_app, :users, :start]
      assert user_stop_event == [:my_app, :users, :stop]

      # Test PaymentActions with [:my_app, :payments] prefix
      PaymentActions.run(:process_payment, %{}, %{"amount" => "100"})

      {:ok, {payment_start_event, _, _}} = TelemetryHelper.receive_event()
      {:ok, {payment_stop_event, _, _}} = TelemetryHelper.receive_event()

      assert payment_start_event == [:my_app, :payments, :start]
      assert payment_stop_event == [:my_app, :payments, :stop]
    end
  end

  describe "parameter validation integration" do
    test "parameter validation errors emit error telemetry" do
      admin_user = %{id: "admin_123", role: "admin"}
      assigns = %{current_user: admin_user}
      # Missing required email field
      params = %{"name" => "Test User"}

      result = UserActions.run(:create_user, assigns, params)
      assert {:error, %{reason: :invalid_params, changeset: changeset}} = result
      refute changeset.valid?

      # Skip start event, get stop event
      {:ok, {_start_event, _start_measurements, _start_metadata}} =
        TelemetryHelper.receive_event()

      {:ok, {stop_event, _stop_measurements, stop_metadata}} = TelemetryHelper.receive_event()

      assert stop_event == [:my_app, :users, :stop]
      assert stop_metadata[:result_type] == :error
    end
  end

  describe "user context in telemetry" do
    test "telemetry includes user_id when current_user is present" do
      user = %{id: "user_456", role: "admin"}
      assigns = %{current_user: user}
      params = %{"email" => "test@example.com", "name" => "Test User"}

      UserActions.run(:create_user, assigns, params)

      {:ok, {_start_event, _start_measurements, start_metadata}} = TelemetryHelper.receive_event()
      {:ok, {_stop_event, _stop_measurements, stop_metadata}} = TelemetryHelper.receive_event()

      assert start_metadata[:user_id] == "user_456"
      assert stop_metadata[:user_id] == "user_456"
    end

    test "telemetry user_id is nil when no current_user" do
      # No current_user
      assigns = %{}
      params = %{"amount" => "50"}

      PaymentActions.run(:process_payment, assigns, params)

      {:ok, {_start_event, _start_measurements, start_metadata}} = TelemetryHelper.receive_event()
      {:ok, {_stop_event, _stop_measurements, stop_metadata}} = TelemetryHelper.receive_event()

      assert start_metadata[:user_id] == nil
      assert stop_metadata[:user_id] == nil
    end
  end

  describe "telemetry performance characteristics" do
    test "telemetry does not affect action performance significantly" do
      admin_user = %{id: "admin_123", role: "admin"}
      assigns = %{current_user: admin_user}
      params = %{"email" => "test@example.com", "name" => "Test User"}

      # Measure execution time
      {time_microseconds, result} =
        :timer.tc(fn ->
          UserActions.run(:create_user, assigns, params)
        end)

      assert {:ok, _} = result
      # Should complete in reasonable time (< 10ms for simple action)
      assert time_microseconds < 10_000

      # Verify telemetry events were still emitted
      {:ok, {_start_event, _start_measurements, _start_metadata}} =
        TelemetryHelper.receive_event()

      {:ok, {_stop_event, _stop_measurements, _stop_metadata}} = TelemetryHelper.receive_event()
    end
  end
end
