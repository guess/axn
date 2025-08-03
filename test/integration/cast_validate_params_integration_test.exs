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
end
