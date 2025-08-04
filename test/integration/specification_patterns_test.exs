defmodule AxnSpecificationPatternsTest do
  @moduledoc """
  Tests all the usage patterns documented in the Axn specification.
  This ensures that every example in the spec actually works.
  """
  use ExUnit.Case, async: true
  import Axn.TestHelpers
  alias Axn.Context

  @moduletag :integration

  describe "simple action pattern" do
    defmodule SimpleActions do
      use Axn

      action :ping do
        step :handle_ping

        def handle_ping(ctx) do
          {:cont, Context.put_result(ctx, "pong")}
        end
      end
    end

    test "ping action works as specified" do
      assert {:ok, "pong"} = SimpleActions.run(:ping, %{}, %{})
    end
  end

  describe "complex action pattern" do
    defmodule ComplexActions do
      use Axn

      action :create_user do
        step :cast_validate_params, schema: %{email!: :string, name!: :string}
        step :require_admin
        step :validate_business_rules
        step :handle_create_user

        def require_admin(ctx) do
          if admin?(ctx.assigns.current_user) do
            {:cont, ctx}
          else
            {:halt, {:error, :unauthorized}}
          end
        end

        def validate_business_rules(ctx) do
          # Example business rule: email must not be from blocked domains
          if String.ends_with?(ctx.params.email, "@blocked.com") do
            {:halt, {:error, :blocked_domain}}
          else
            {:cont, ctx}
          end
        end

        def handle_create_user(ctx) do
          user = %{
            id: :rand.uniform(10000),
            email: ctx.params.email,
            name: ctx.params.name,
            created_at: DateTime.utc_now()
          }

          {:halt, {:ok, %{message: "User created", user: user}}}
        end

        defp admin?(user), do: user && user.role == "admin"
      end
    end

    test "successful user creation" do
      assigns = %{current_user: build_user(role: "admin")}
      params = %{"email" => "test@example.com", "name" => "John Doe"}

      assert_action_succeeds(
        ComplexActions.run(:create_user, assigns, params),
        fn result ->
          assert result.message == "User created"
          assert result.user.email == "test@example.com"
          assert result.user.name == "John Doe"
        end
      )
    end

    test "fails authorization" do
      assigns = %{current_user: build_user(role: "user")}
      params = %{"email" => "test@example.com", "name" => "John Doe"}

      assert_action_fails(
        ComplexActions.run(:create_user, assigns, params),
        :unauthorized
      )
    end

    test "fails business rules validation" do
      assigns = %{current_user: build_user(role: "admin")}
      params = %{"email" => "test@blocked.com", "name" => "John Doe"}

      assert_action_fails(
        ComplexActions.run(:create_user, assigns, params),
        :blocked_domain
      )
    end

    test "fails parameter validation" do
      assigns = %{current_user: build_user(role: "admin")}
      # Missing name
      params = %{"email" => "test@example.com"}

      assert_action_fails(
        ComplexActions.run(:create_user, assigns, params),
        %{reason: :invalid_params, changeset: changeset},
        fn error_details ->
          refute error_details.changeset.valid?
          assert error_details.changeset.errors[:name]
        end
      )
    end
  end

  describe "action with custom validation pattern" do
    defmodule CustomValidationActions do
      use Axn

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
          token = Ecto.Changeset.get_field(changeset, :challenge_token)

          changeset =
            if phone && String.starts_with?(phone, "+") do
              changeset
            else
              Ecto.Changeset.add_error(changeset, :phone, "must start with +")
            end

          if token && String.length(token) >= 6 do
            changeset
          else
            Ecto.Changeset.add_error(changeset, :challenge_token, "must be at least 6 characters")
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
          otp_code = :rand.uniform(999_999) |> Integer.to_string() |> String.pad_leading(6, "0")

          result = %{
            message: "OTP sent",
            phone: ctx.params.phone,
            region: ctx.params.region,
            expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
          }

          {:halt, {:ok, result}}
        end
      end
    end

    test "successful OTP request with custom validation" do
      assigns = %{current_user: build_user()}

      params = %{
        "phone" => "+1234567890",
        "challenge_token" => "abcdef123"
      }

      assert_action_succeeds(
        CustomValidationActions.run(:request_otp, assigns, params),
        fn result ->
          assert result.message == "OTP sent"
          assert result.phone == "+1234567890"
          # Default value
          assert result.region == "US"
          assert %DateTime{} = result.expires_at
        end
      )
    end

    test "fails custom phone validation" do
      assigns = %{current_user: build_user()}

      params = %{
        # Missing +
        "phone" => "1234567890",
        "challenge_token" => "abcdef123"
      }

      assert_action_fails(
        CustomValidationActions.run(:request_otp, assigns, params),
        %{reason: :invalid_params, changeset: changeset}
      ) do
        refute changeset.valid?
        assert {"must start with +", []} in changeset.errors[:phone]
      end
    end

    test "fails custom token validation" do
      assigns = %{current_user: build_user()}

      params = %{
        "phone" => "+1234567890",
        # Too short
        "challenge_token" => "abc"
      }

      assert_action_fails(
        CustomValidationActions.run(:request_otp, assigns, params),
        %{reason: :invalid_params, changeset: changeset}
      ) do
        refute changeset.valid?
        assert {"must be at least 6 characters", []} in changeset.errors[:challenge_token]
      end
    end

    test "uses default region value" do
      assigns = %{current_user: build_user()}

      params = %{
        "phone" => "+1234567890",
        "challenge_token" => "abcdef123"
        # No region specified - should use default "US"
      }

      assert_action_succeeds(
        CustomValidationActions.run(:request_otp, assigns, params),
        fn result ->
          assert result.region == "US"
        end
      )
    end

    test "explicit region overrides default" do
      assigns = %{current_user: build_user()}

      params = %{
        "phone" => "+441234567890",
        "region" => "UK",
        "challenge_token" => "abcdef123"
      }

      assert_action_succeeds(
        CustomValidationActions.run(:request_otp, assigns, params),
        fn result ->
          assert result.region == "UK"
        end
      )
    end
  end

  describe "external steps pattern" do
    defmodule ExternalSteps do
      def enrich_context(ctx, opts) do
        fields = Keyword.get(opts, :fields, [])

        enriched_data =
          Enum.reduce(fields, %{}, fn field, acc ->
            case field do
              :preferences -> Map.put(acc, :preferences, %{theme: "dark", language: "en"})
              :billing -> Map.put(acc, :billing, %{plan: "premium", expires: Date.utc_today()})
              _ -> acc
            end
          end)

        {:cont, Context.assign(ctx, enriched_data)}
      end

      def validate_external_service(ctx, _opts) do
        # Simulate external service validation
        if ctx.assigns[:preferences] do
          {:cont, Context.assign(ctx, :external_validated, true)}
        else
          {:halt, {:error, :external_service_unavailable}}
        end
      end
    end

    defmodule ExternalStepsActions do
      use Axn

      action :complex_operation do
        step :cast_validate_params, schema: %{data!: :string}
        step :require_admin
        step {ExternalSteps, :enrich_context}, fields: [:preferences, :billing]
        step {ExternalSteps, :validate_external_service}
        step :handle_operation

        def require_admin(ctx) do
          if admin?(ctx.assigns.current_user) do
            {:cont, ctx}
          else
            {:halt, {:error, :unauthorized}}
          end
        end

        def handle_operation(ctx) do
          result = %{
            data: ctx.params.data,
            preferences: ctx.assigns.preferences,
            billing: ctx.assigns.billing,
            validated: ctx.assigns.external_validated
          }

          {:halt, {:ok, result}}
        end

        defp admin?(user), do: user && user.role == "admin"
      end
    end

    test "external steps work correctly" do
      assigns = %{current_user: build_user(role: "admin")}
      params = %{"data" => "test data"}

      assert_action_succeeds(
        ExternalStepsActions.run(:complex_operation, assigns, params),
        fn result ->
          assert result.data == "test data"
          assert result.preferences == %{theme: "dark", language: "en"}
          assert result.billing.plan == "premium"
          assert result.validated == true
        end
      )
    end
  end

  describe "context helper patterns" do
    defmodule ContextHelperActions do
      use Axn

      action :test_context_helpers do
        step :test_assign_patterns
        step :test_private_patterns
        step :test_params_patterns

        def test_assign_patterns(ctx) do
          # Test different assign patterns from spec
          ctx = Context.assign(ctx, :single_value, "test")
          ctx = Context.assign(ctx, %{map_assigns: "value1", other: "value2"})
          ctx = Context.assign(ctx, keyword_assigns: "value3", more: "value4")

          {:cont, ctx}
        end

        def test_private_patterns(ctx) do
          # Test private data patterns
          ctx = Context.put_private(ctx, :correlation_id, "abc-123")
          ctx = Context.put_private(ctx, :changeset, %{valid?: true})

          correlation_id = Context.get_private(ctx, :correlation_id)
          default_value = Context.get_private(ctx, :missing_key, "default")

          ctx = Context.assign(ctx, :correlation_id, correlation_id)
          ctx = Context.assign(ctx, :default_value, default_value)

          {:cont, ctx}
        end

        def test_params_patterns(ctx) do
          # Test params update
          new_params = Map.put(ctx.params, :processed, true)
          ctx = Context.put_params(ctx, new_params)

          {:halt,
           {:ok,
            %{
              assigns: ctx.assigns,
              params: ctx.params,
              has_private_changeset: not is_nil(Context.get_private(ctx, :changeset))
            }}}
        end
      end
    end

    test "context helper functions work as specified" do
      assigns = %{}
      params = %{"input" => "test"}

      assert_action_succeeds(
        ContextHelperActions.run(:test_context_helpers, assigns, params),
        fn result ->
          # Check assign patterns worked
          assert result.assigns.single_value == "test"
          assert result.assigns.map_assigns == "value1"
          assert result.assigns.other == "value2"
          assert result.assigns.keyword_assigns == "value3"
          assert result.assigns.more == "value4"

          # Check private patterns worked
          assert result.assigns.correlation_id == "abc-123"
          assert result.assigns.default_value == "default"
          assert result.has_private_changeset == true

          # Check params patterns worked
          assert result.params.processed == true
          # Original param preserved
          assert result.params["input"] == "test"
        end
      )
    end
  end

  describe "authorization patterns from specification" do
    defmodule AuthorizationPatternActions do
      use Axn

      # Pattern 1: Simple role check
      action :admin_only_action do
        step :require_admin
        step :handle_action

        def require_admin(ctx) do
          if admin?(ctx.assigns.current_user) do
            {:cont, ctx}
          else
            {:halt, {:error, :unauthorized}}
          end
        end

        def handle_action(ctx) do
          {:halt, {:ok, "admin action completed"}}
        end

        defp admin?(user), do: user && user.role == "admin"
      end

      # Pattern 2: Resource-based authorization
      action :user_access_action do
        step :cast_validate_params, schema: %{user_id!: :integer}
        step :authorize_user_access
        step :handle_action

        def authorize_user_access(ctx) do
          if can_access?(ctx.assigns.current_user, ctx.params.user_id) do
            {:cont, ctx}
          else
            {:halt, {:error, :unauthorized}}
          end
        end

        def handle_action(ctx) do
          {:halt, {:ok, "user access granted"}}
        end

        defp can_access?(user, user_id) do
          user && (user.id == user_id || user.role == "admin")
        end
      end

      # Pattern 3: Action-based authorization
      action :action_based_auth do
        step :authorize_action
        step :handle_action

        def authorize_action(ctx) do
          if allowed?(ctx.assigns.current_user, ctx.action) do
            {:cont, ctx}
          else
            {:halt, {:error, :unauthorized}}
          end
        end

        def handle_action(ctx) do
          {:halt, {:ok, "action authorized"}}
        end

        defp allowed?(user, :action_based_auth) do
          user && user.role in ["admin", "moderator"]
        end
      end
    end

    test "simple role check pattern works" do
      # Success case
      assigns = %{current_user: build_user(role: "admin")}

      assert_action_succeeds(
        AuthorizationPatternActions.run(:admin_only_action, assigns, %{}),
        fn result -> assert result == "admin action completed" end
      )

      # Failure case
      assigns = %{current_user: build_user(role: "user")}

      assert_action_fails(
        AuthorizationPatternActions.run(:admin_only_action, assigns, %{}),
        :unauthorized
      )
    end

    test "resource-based authorization pattern works" do
      user = build_user(id: 123, role: "user")

      # User can access their own resource
      assigns = %{current_user: user}
      params = %{"user_id" => "123"}

      assert_action_succeeds(
        AuthorizationPatternActions.run(:user_access_action, assigns, params),
        fn result -> assert result == "user access granted" end
      )

      # User cannot access other's resource
      params = %{"user_id" => "456"}

      assert_action_fails(
        AuthorizationPatternActions.run(:user_access_action, assigns, params),
        :unauthorized
      )

      # Admin can access any resource
      admin = build_user(id: 789, role: "admin")
      assigns = %{current_user: admin}
      params = %{"user_id" => "123"}

      assert_action_succeeds(
        AuthorizationPatternActions.run(:user_access_action, assigns, params),
        fn result -> assert result == "user access granted" end
      )
    end

    test "action-based authorization pattern works" do
      # Moderator can access
      assigns = %{current_user: build_user(role: "moderator")}

      assert_action_succeeds(
        AuthorizationPatternActions.run(:action_based_auth, assigns, %{}),
        fn result -> assert result == "action authorized" end
      )

      # Regular user cannot access
      assigns = %{current_user: build_user(role: "user")}

      assert_action_fails(
        AuthorizationPatternActions.run(:action_based_auth, assigns, %{}),
        :unauthorized
      )
    end
  end

  describe "telemetry configuration patterns" do
    defmodule TelemetryConfigActions do
      use Axn, telemetry_prefix: [:spec_test, :custom]

      action :test_action do
        step :handle_test

        def handle_test(ctx) do
          {:halt, {:ok, "test completed"}}
        end
      end
    end

    defmodule DefaultTelemetryActions do
      # No telemetry_prefix - should use [:axn]
      use Axn

      action :test_action do
        step :handle_test

        def handle_test(ctx) do
          {:halt, {:ok, "test completed"}}
        end
      end
    end

    test "custom telemetry prefix works" do
      events = capture_telemetry([[:spec_test, :custom]])

      TelemetryConfigActions.run(:test_action, %{current_user: build_user(id: 123)}, %{})

      captured = events.()
      assert length(captured) == 2

      {start_event, _measurements, start_metadata} =
        Enum.find(captured, fn {event, _, _} ->
          List.last(event) == :start
        end)

      {stop_event, _measurements, stop_metadata} =
        Enum.find(captured, fn {event, _, _} ->
          List.last(event) == :stop
        end)

      assert start_event == [:spec_test, :custom, :start]
      assert stop_event == [:spec_test, :custom, :stop]
      assert start_metadata.action == :test_action
      assert stop_metadata.action == :test_action
      assert stop_metadata.user_id == 123
      assert stop_metadata.result_type == :ok
    end

    test "default telemetry prefix works" do
      events = capture_telemetry([[:axn]])

      DefaultTelemetryActions.run(:test_action, %{current_user: build_user(id: 456)}, %{})

      captured = events.()
      assert length(captured) == 2

      {start_event, _measurements, _start_metadata} =
        Enum.find(captured, fn {event, _, _} ->
          List.last(event) == :start
        end)

      assert start_event == [:axn, :start]
    end
  end
end
