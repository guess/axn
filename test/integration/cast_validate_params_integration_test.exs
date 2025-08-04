defmodule Integration.CastValidateParamsIntegrationTest do
  use ExUnit.Case

  @moduletag :integration

  describe "parameter validation and type casting" do
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

    test "handles defaults and optional fields" do
      defmodule DefaultsActions do
        use Axn, telemetry_prefix: [:test, :defaults]

        action :with_defaults do
          step :cast_validate_params,
            schema: %{
              email!: :string,
              name!: :string,
              age: :integer,
              region: [field: :string, default: "US"],
              subscribe_newsletter: [field: :boolean, default: false]
            }

          step :return_params

          def return_params(ctx) do
            {:cont, put_result(ctx, ctx.params)}
          end
        end
      end

      # Test with minimal required params - should get defaults
      params = %{
        "email" => "john@example.com",
        "name" => "John Doe"
      }

      assert {:ok, result} = DefaultsActions.run(:with_defaults, %{}, params)
      assert result.email == "john@example.com"
      assert result.name == "John Doe"
      # Default value
      assert result.region == "US"
      # Default value
      assert result.subscribe_newsletter == false
      # Optional field not provided
      assert is_nil(result[:age])

      # Test overriding defaults
      params_with_overrides = %{
        "email" => "jane@example.com",
        "name" => "Jane Doe",
        "age" => "30",
        "region" => "CA",
        "subscribe_newsletter" => "true"
      }

      assert {:ok, result} = DefaultsActions.run(:with_defaults, %{}, params_with_overrides)
      assert result.email == "jane@example.com"
      assert result.name == "Jane Doe"
      assert result.age == 30
      # Overridden default
      assert result.region == "CA"
      # Overridden default
      assert result.subscribe_newsletter == true
    end

    test "validation errors with detailed changeset information" do
      defmodule ValidationErrorsActions do
        use Axn, telemetry_prefix: [:test, :validation_errors]

        action :validate_strict do
          step :cast_validate_params, schema: %{email!: :string, age!: :integer, score!: :float}
          step :return_params

          def return_params(ctx) do
            {:cont, put_result(ctx, ctx.params)}
          end
        end
      end

      # Test multiple validation errors
      invalid_params = %{
        "age" => "not_a_number",
        "score" => "not_a_float"
        # email missing (required)
      }

      assert {:error, %{reason: :invalid_params, changeset: changeset}} =
               ValidationErrorsActions.run(:validate_strict, %{}, invalid_params)

      refute changeset.valid?

      # Should have errors for all problematic fields
      errors = changeset.errors
      assert errors[:email] == {"can't be blank", [validation: :required]}
      assert errors[:age] == {"is invalid", [type: :integer, validation: :cast]}
      assert errors[:score] == {"is invalid", [type: :float, validation: :cast]}
    end
  end
end
