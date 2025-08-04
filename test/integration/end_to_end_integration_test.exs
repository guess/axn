defmodule AxnEndToEndIntegrationTest do
  use ExUnit.Case, async: true
  alias Axn.Context

  @moduletag :integration

  # Example User Actions module for testing
  defmodule TestUserActions do
    use Axn, telemetry_prefix: [:test_app, :users]

    action :create_user do
      step :cast_validate_params, schema: %{email!: :string, name!: :string}
      step :require_admin
      step :handle_create

      def require_admin(ctx) do
        if admin?(ctx.assigns.current_user) do
          {:cont, ctx}
        else
          {:halt, {:error, :unauthorized}}
        end
      end

      def handle_create(ctx) do
        user = %{
          id: :rand.uniform(10000),
          email: ctx.params.email,
          name: ctx.params.name,
          created_at: DateTime.utc_now()
        }

        {:halt, {:ok, user}}
      end

      defp admin?(user), do: user && user.role == "admin"
    end

    action :ping do
      step :handle_ping

      def handle_ping(ctx) do
        {:cont, Context.put_result(ctx, "pong")}
      end
    end

    action :complex_operation do
      step :cast_validate_params, schema: %{data!: :string, count: [field: :integer, default: 1]}
      step :validate_data
      step :process_data
      step :finalize

      def validate_data(ctx) do
        if String.length(ctx.params.data) > 100 do
          {:halt, {:error, :data_too_large}}
        else
          {:cont, ctx}
        end
      end

      def process_data(ctx) do
        processed = String.upcase(ctx.params.data)
        {:cont, Context.assign(ctx, :processed_data, processed)}
      end

      def finalize(ctx) do
        result = %{
          processed: ctx.assigns.processed_data,
          count: ctx.params.count,
          timestamp: DateTime.utc_now()
        }

        {:halt, {:ok, result}}
      end
    end
  end

  # Example Auth Actions module for testing
  defmodule TestAuthActions do
    use Axn, telemetry_prefix: [:test_app, :auth]

    action :request_otp do
      step :cast_validate_params,
        schema: %{
          phone!: :string,
          region: [field: :string, default: "US"],
          challenge_token!: :string
        },
        validate: &__MODULE__.validate_phone_and_token/1

      step :require_authenticated_user
      step :handle_request

      def validate_phone_and_token(changeset) do
        # Simulate phone validation
        phone = Ecto.Changeset.get_field(changeset, :phone)

        if phone && String.starts_with?(phone, "+") do
          changeset
        else
          Ecto.Changeset.add_error(changeset, :phone, "must start with +")
        end
      end

      def require_authenticated_user(ctx) do
        if ctx.assigns[:current_user] do
          {:cont, ctx}
        else
          {:halt, {:error, :unauthenticated}}
        end
      end

      def handle_request(ctx) do
        # Simulate OTP generation and sending
        otp_code = :rand.uniform(999_999) |> Integer.to_string() |> String.pad_leading(6, "0")

        result = %{
          message: "OTP sent",
          phone: ctx.params.phone,
          otp_code: otp_code,
          expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
        }

        {:halt, {:ok, result}}
      end
    end
  end

  describe "end-to-end user actions" do
    test "create_user succeeds with admin user and valid params" do
      assigns = %{current_user: %{id: 123, role: "admin"}}
      params = %{"email" => "test@example.com", "name" => "John Doe"}

      assert {:ok, user} = TestUserActions.run(:create_user, assigns, params)
      assert user.email == "test@example.com"
      assert user.name == "John Doe"
      assert is_integer(user.id)
      assert %DateTime{} = user.created_at
    end

    test "create_user fails with non-admin user" do
      assigns = %{current_user: %{id: 123, role: "user"}}
      params = %{"email" => "test@example.com", "name" => "John Doe"}

      assert {:error, :unauthorized} = TestUserActions.run(:create_user, assigns, params)
    end

    test "create_user fails with invalid params" do
      assigns = %{current_user: %{id: 123, role: "admin"}}
      # Missing required name
      params = %{"email" => "test@example.com"}

      assert {:error, %{reason: :invalid_params, changeset: changeset}} =
               TestUserActions.run(:create_user, assigns, params)

      refute changeset.valid?
      assert changeset.errors[:name]
    end

    test "ping action returns simple result" do
      assigns = %{}
      params = %{}

      assert {:ok, "pong"} = TestUserActions.run(:ping, assigns, params)
    end

    test "complex_operation processes data successfully" do
      assigns = %{}
      params = %{"data" => "hello world", "count" => "5"}

      assert {:ok, result} = TestUserActions.run(:complex_operation, assigns, params)
      assert result.processed == "HELLO WORLD"
      assert result.count == 5
      assert %DateTime{} = result.timestamp
    end

    test "complex_operation fails with data too large" do
      assigns = %{}
      large_data = String.duplicate("x", 101)
      params = %{"data" => large_data}

      assert {:error, :data_too_large} = TestUserActions.run(:complex_operation, assigns, params)
    end

    test "complex_operation uses default values" do
      assigns = %{}
      params = %{"data" => "test"}

      assert {:ok, result} = TestUserActions.run(:complex_operation, assigns, params)
      # Default value
      assert result.count == 1
    end
  end

  describe "end-to-end auth actions" do
    test "request_otp succeeds with valid input" do
      assigns = %{current_user: %{id: 123}}
      params = %{"phone" => "+1234567890", "challenge_token" => "abc123"}

      assert {:ok, result} = TestAuthActions.run(:request_otp, assigns, params)
      assert result.message == "OTP sent"
      assert result.phone == "+1234567890"
      assert String.length(result.otp_code) == 6
      assert %DateTime{} = result.expires_at
    end

    test "request_otp fails without authentication" do
      # No current_user
      assigns = %{}
      params = %{"phone" => "+1234567890", "challenge_token" => "abc123"}

      assert {:error, :unauthenticated} = TestAuthActions.run(:request_otp, assigns, params)
    end

    test "request_otp fails with invalid phone format" do
      assigns = %{current_user: %{id: 123}}
      # Missing +
      params = %{"phone" => "1234567890", "challenge_token" => "abc123"}

      assert {:error, %{reason: :invalid_params, changeset: changeset}} =
               TestAuthActions.run(:request_otp, assigns, params)

      refute changeset.valid?
      assert changeset.errors[:phone]
    end

    test "request_otp uses default region" do
      assigns = %{current_user: %{id: 123}}
      params = %{"phone" => "+1234567890", "challenge_token" => "abc123"}

      assert {:ok, result} = TestAuthActions.run(:request_otp, assigns, params)
      # The action should work even without explicit region (uses default "US")
      assert result.message == "OTP sent"
    end
  end

  describe "telemetry integration in real actions" do
    setup do
      # Capture telemetry events
      test_pid = self()

      :telemetry.attach_many(
        "test-telemetry",
        [
          [:test_app, :users, :start],
          [:test_app, :users, :stop],
          [:test_app, :auth, :start],
          [:test_app, :auth, :stop]
        ],
        &__MODULE__.handle_telemetry_event/4,
        test_pid
      )

      on_exit(fn -> :telemetry.detach("test-telemetry") end)
    end

    test "user actions emit telemetry events" do
      assigns = %{current_user: %{id: 123, role: "admin"}}
      params = %{"email" => "test@example.com", "name" => "John Doe"}

      {:ok, _user} = TestUserActions.run(:create_user, assigns, params)

      # Should receive start and stop events
      assert_receive {:telemetry, [:test_app, :users, :start], _measurements, metadata}
      assert metadata.action == :create_user

      assert_receive {:telemetry, [:test_app, :users, :stop], measurements, metadata}
      assert metadata.action == :create_user
      assert metadata.result_type == :ok
      assert metadata.user_id == "123"
      assert is_integer(measurements.duration)
    end

    test "auth actions emit telemetry events with failure" do
      # No current_user - will fail
      assigns = %{}
      params = %{"phone" => "+1234567890", "challenge_token" => "abc123"}

      {:error, :unauthenticated} = TestAuthActions.run(:request_otp, assigns, params)

      # Should receive start and stop events
      assert_receive {:telemetry, [:test_app, :auth, :start], _measurements, metadata}
      assert metadata.action == :request_otp

      assert_receive {:telemetry, [:test_app, :auth, :stop], measurements, metadata}
      assert metadata.action == :request_otp
      assert metadata.result_type == :error
      # No user
      assert is_nil(metadata.user_id)
      assert is_integer(measurements.duration)
    end
  end

  describe "error handling edge cases" do
    defmodule ErrorTestActions do
      use Axn

      action :step_raises_exception do
        step :raise_error

        def raise_error(_ctx) do
          raise "Something went wrong"
        end
      end

      action :step_returns_invalid_format do
        step :bad_return

        def bad_return(_ctx) do
          :invalid_return_format
        end
      end
    end

    test "handles step exceptions gracefully" do
      assigns = %{}
      params = %{}

      assert {:error, %{reason: :step_exception}} =
               ErrorTestActions.run(:step_raises_exception, assigns, params)
    end

    test "handles invalid step return formats" do
      assigns = %{}
      params = %{}

      assert {:error, %{reason: :step_exception}} =
               ErrorTestActions.run(:step_returns_invalid_format, assigns, params)
    end
  end

  @doc false
  def handle_telemetry_event(event, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry, event, measurements, metadata})
  end
end
