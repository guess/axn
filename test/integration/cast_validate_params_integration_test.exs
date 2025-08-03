defmodule Integration.CastValidateParamsIntegrationTest do
  use ExUnit.Case
  @moduletag :integration

  describe "basic integration with Axn DSL" do
    test "can use cast_validate_params as atom step in action" do
      defmodule BasicActionModule do
        use Axn, telemetry_prefix: [:test, :basic]

        action :test_params do
          step :cast_validate_params, schema: %{name!: :string}
        end
      end

      # The integration should work successfully
      assert {:ok, nil} = BasicActionModule.run(:test_params, %{}, %{"name" => "John"})
    end

    test "validates required fields and returns casted params" do
      defmodule ValidationActionModule do
        use Axn, telemetry_prefix: [:test, :validation]

        action :validate_user do
          step :cast_validate_params, schema: %{name!: :string, age: :integer}
          step :return_params

          def return_params(ctx) do
            {:cont, put_result(ctx, ctx.params)}
          end
        end
      end

      # Should succeed with valid params
      assert {:ok, %{name: "John", age: 25}} =
               ValidationActionModule.run(:validate_user, %{}, %{"name" => "John", "age" => "25"})

      # Should fail with missing required field
      assert {:error, %{reason: :invalid_params, changeset: changeset}} =
               ValidationActionModule.run(:validate_user, %{}, %{"age" => "25"})

      refute changeset.valid?
    end
  end

  describe "type casting capabilities" do
    test "casts string inputs to proper types" do
      defmodule TypeCastingActions do
        use Axn, telemetry_prefix: [:test, :casting]

        action :cast_types do
          step :cast_validate_params,
            schema: %{
              name!: :string,
              age: :integer,
              active: :boolean,
              score: :float
            }

          step :return_casted_params

          def return_casted_params(ctx) do
            {:cont, put_result(ctx, ctx.params)}
          end
        end
      end

      # Test type casting
      string_params = %{
        "name" => "John",
        "age" => "25",
        "active" => "true",
        "score" => "9.5"
      }

      assert {:ok, casted_params} = TypeCastingActions.run(:cast_types, %{}, string_params)
      assert casted_params.name == "John"
      assert casted_params.age == 25
      assert casted_params.active == true
      assert casted_params.score == 9.5

      # Test invalid casting
      invalid_params = %{
        "name" => "John",
        "age" => "not_a_number"
      }

      assert {:error, %{reason: :invalid_params, changeset: changeset}} =
               TypeCastingActions.run(:cast_types, %{}, invalid_params)

      refute changeset.valid?
      assert changeset.errors[:age] == {"is invalid", [type: :integer, validation: :cast]}
    end
  end

  describe "real-world scenario" do
    test "complete user registration action with defaults and validation" do
      defmodule UserRegistrationActions do
        use Axn, telemetry_prefix: [:test, :user_registration]

        action :register_user do
          step :cast_validate_params,
            schema: %{
              email!: :string,
              name!: :string,
              age: :integer,
              region: [field: :string, default: "US"],
              subscribe_newsletter: [field: :boolean, default: false]
            }

          step :create_user

          def create_user(ctx) do
            # Simulate user creation
            user = Map.put(ctx.params, :id, 123)
            {:cont, put_result(ctx, user)}
          end
        end
      end

      # Test successful registration with defaults
      valid_params = %{
        "email" => "john@example.com",
        "name" => "John Doe",
        "age" => "25"
      }

      assert {:ok, user} = UserRegistrationActions.run(:register_user, %{}, valid_params)
      assert user.email == "john@example.com"
      assert user.name == "John Doe"
      assert user.age == 25
      # Default value
      assert user.region == "US"
      # Default value
      assert user.subscribe_newsletter == false
      assert user.id == 123

      # Test missing required field
      missing_params = %{"name" => "John Doe"}

      assert {:error, %{reason: :invalid_params, changeset: changeset}} =
               UserRegistrationActions.run(:register_user, %{}, missing_params)

      refute changeset.valid?
      assert changeset.errors[:email] == {"can't be blank", [validation: :required]}
    end
  end

  describe "authorization patterns" do
    test "simple role-based authorization" do
      defmodule AdminActions do
        use Axn, telemetry_prefix: [:test, :admin]

        action :admin_only_action do
          step :require_admin
          step :perform_admin_task

          def require_admin(ctx) do
            if admin?(ctx.assigns[:current_user]) do
              {:cont, ctx}
            else
              {:halt, {:error, :unauthorized}}
            end
          end

          def perform_admin_task(ctx) do
            {:cont, put_result(ctx, "Admin task completed")}
          end

          defp admin?(user), do: user && user.role == "admin"
        end
      end

      # Test successful admin access
      admin_user = %{id: 1, role: "admin"}
      assigns = %{current_user: admin_user}

      assert {:ok, "Admin task completed"} = AdminActions.run(:admin_only_action, assigns, %{})

      # Test unauthorized access
      regular_user = %{id: 2, role: "user"}
      assigns = %{current_user: regular_user}

      assert {:error, :unauthorized} = AdminActions.run(:admin_only_action, assigns, %{})

      # Test no user
      assert {:error, :unauthorized} = AdminActions.run(:admin_only_action, %{}, %{})
    end

    test "resource-based authorization" do
      defmodule UserActions do
        use Axn, telemetry_prefix: [:test, :user_auth]

        action :update_user do
          step :cast_validate_params, schema: %{user_id!: :integer, name: :string}
          step :authorize_user_access
          step :update_user_record

          def authorize_user_access(ctx) do
            current_user = ctx.assigns[:current_user]
            target_user_id = ctx.params.user_id

            if can_access?(current_user, target_user_id) do
              {:cont, ctx}
            else
              {:halt, {:error, :unauthorized}}
            end
          end

          def update_user_record(ctx) do
            {:cont, put_result(ctx, "User updated successfully")}
          end

          defp can_access?(user, target_user_id) do
            user && (user.id == target_user_id || user.role == "admin")
          end
        end
      end

      # Test user updating their own record
      user = %{id: 123, role: "user"}
      assigns = %{current_user: user}
      params = %{"user_id" => "123", "name" => "New Name"}

      assert {:ok, "User updated successfully"} = UserActions.run(:update_user, assigns, params)

      # Test admin updating another user's record
      admin = %{id: 456, role: "admin"}
      assigns = %{current_user: admin}

      assert {:ok, "User updated successfully"} = UserActions.run(:update_user, assigns, params)

      # Test unauthorized access (different user, not admin)
      other_user = %{id: 789, role: "user"}
      assigns = %{current_user: other_user}

      assert {:error, :unauthorized} = UserActions.run(:update_user, assigns, params)
    end
  end
end
