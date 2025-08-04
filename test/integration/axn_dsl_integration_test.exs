defmodule Integration.AxnDslIntegrationTest do
  use ExUnit.Case

  @moduletag :integration

  describe "basic DSL integration" do
    test "can use cast_validate_params as built-in step" do
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
end
