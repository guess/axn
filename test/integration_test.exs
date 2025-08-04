defmodule AxnIntegrationTest do
  @moduledoc """
  Core integration tests covering end-to-end functionality.
  
  These tests verify that the main usage patterns work correctly
  with real-world scenarios.
  """
  use ExUnit.Case, async: true
  alias Axn.Context

  @moduletag :integration

  # Example application module
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

  # Example with custom validation
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
          {:halt, {:error, :authentication_required}}
        end
      end

      def handle_request(ctx) do
        # Simulate OTP generation
        otp_data = %{
          phone: ctx.params.phone,
          region: ctx.params.region,
          otp_code: :rand.uniform(999999) |> Integer.to_string() |> String.pad_leading(6, "0"),
          expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
        }

        {:halt, {:ok, %{message: "OTP sent", data: otp_data}}}
      end
    end
  end

  describe "end-to-end user creation flow" do
    test "successful user creation with admin user" do
      assigns = %{current_user: %{id: 123, role: "admin"}}
      params = %{"email" => "user@example.com", "name" => "John Doe"}

      assert {:ok, user} = TestUserActions.run(:create_user, assigns, params)
      assert user.email == "user@example.com"
      assert user.name == "John Doe"
      assert is_integer(user.id)
      assert %DateTime{} = user.created_at
    end

    test "authorization failure with non-admin user" do
      assigns = %{current_user: %{id: 123, role: "user"}}
      params = %{"email" => "user@example.com", "name" => "John Doe"}

      assert {:error, :unauthorized} = TestUserActions.run(:create_user, assigns, params)
    end

    test "parameter validation failure" do
      assigns = %{current_user: %{id: 123, role: "admin"}}
      params = %{"email" => "user@example.com"}  # Missing required name

      assert {:error, %{reason: :invalid_params, changeset: changeset}} = 
        TestUserActions.run(:create_user, assigns, params)
      
      refute changeset.valid?
      assert changeset.errors[:name]
    end
  end

  describe "complex multi-step operation" do
    test "successful processing with defaults" do
      assigns = %{}
      params = %{"data" => "hello world"}

      assert {:ok, result} = TestUserActions.run(:complex_operation, assigns, params)
      assert result.processed == "HELLO WORLD"
      assert result.count == 1  # Default value
      assert %DateTime{} = result.timestamp
    end

    test "successful processing with custom count" do
      assigns = %{}
      params = %{"data" => "test", "count" => "5"}

      assert {:ok, result} = TestUserActions.run(:complex_operation, assigns, params)
      assert result.processed == "TEST"
      assert result.count == 5
    end

    test "validation failure for data too large" do
      assigns = %{}
      large_data = String.duplicate("x", 101)
      params = %{"data" => large_data}

      assert {:error, :data_too_large} = TestUserActions.run(:complex_operation, assigns, params)
    end
  end

  describe "authentication flow with custom validation" do
    test "successful OTP request" do
      assigns = %{current_user: %{id: 123}}
      params = %{
        "phone" => "+1234567890", 
        "region" => "US",
        "challenge_token" => "abc123"
      }

      assert {:ok, response} = TestAuthActions.run(:request_otp, assigns, params)
      assert response.message == "OTP sent"
      assert response.data.phone == "+1234567890"
      assert response.data.region == "US"
      assert String.length(response.data.otp_code) == 6
      assert %DateTime{} = response.data.expires_at
    end

    test "authentication failure" do
      assigns = %{}  # No current_user
      params = %{
        "phone" => "+1234567890",
        "challenge_token" => "abc123"
      }

      assert {:error, :authentication_required} = 
        TestAuthActions.run(:request_otp, assigns, params)
    end

    test "custom validation failure" do
      assigns = %{current_user: %{id: 123}}
      params = %{
        "phone" => "1234567890",  # Missing +
        "challenge_token" => "abc123"
      }

      assert {:error, %{reason: :invalid_params, changeset: changeset}} = 
        TestAuthActions.run(:request_otp, assigns, params)
      
      refute changeset.valid?
      assert changeset.errors[:phone]
    end

    test "uses default region when not provided" do
      assigns = %{current_user: %{id: 123}}
      params = %{
        "phone" => "+1234567890",
        "challenge_token" => "abc123"
      }

      assert {:ok, response} = TestAuthActions.run(:request_otp, assigns, params)
      assert response.data.region == "US"  # Default value
    end
  end

  describe "simple action" do
    test "ping returns pong" do
      assert {:ok, "pong"} = TestUserActions.run(:ping, %{}, %{})
    end
  end

  describe "error handling" do
    test "undefined action returns proper error" do
      assert {:error, :action_not_found} = TestUserActions.run(:nonexistent, %{}, %{})
    end

    test "step exceptions are caught and returned as errors" do
      defmodule FailingActions do
        use Axn

        action :failing_action do
          step :failing_step

          def failing_step(_ctx) do
            raise "Something went wrong"
          end
        end
      end

      assert {:error, _reason} = FailingActions.run(:failing_action, %{}, %{})
    end
  end
end