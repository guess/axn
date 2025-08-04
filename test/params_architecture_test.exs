defmodule ParamsArchitectureTest do
  @moduledoc """
  Tests demonstrating the new params architecture where raw params start in ctx.params
  and are only moved to private when cast_validate_params is used.
  """
  use ExUnit.Case

  describe "new params architecture" do
    defmodule SimpleActions do
      use Axn

      # Action without parameter validation - raw params stay in ctx.params
      action :simple_action do
        step :handle_raw_params

        def handle_raw_params(ctx) do
          # Raw params are directly accessible in ctx.params
          name = ctx.params["name"]
          age_string = ctx.params["age"]

          result = %{
            name: name,
            age_string: age_string,
            raw_params_accessible: true
          }

          {:halt, {:ok, result}}
        end
      end

      # Action with parameter validation - raw params moved to private
      action :validated_action do
        step :cast_validate_params, schema: %{name!: :string, age!: :integer}
        step :handle_cast_params

        def handle_cast_params(ctx) do
          # Cast params are in ctx.params, raw params in ctx.private.raw_params
          # Cast string
          name = ctx.params.name
          # Cast integer
          age = ctx.params.age
          # Original string
          raw_name = ctx.private.raw_params["name"]
          # Original string
          raw_age = ctx.private.raw_params["age"]

          result = %{
            cast_name: name,
            cast_age: age,
            raw_name: raw_name,
            raw_age: raw_age,
            both_accessible: true
          }

          {:halt, {:ok, result}}
        end
      end
    end

    test "raw params are directly accessible without validation" do
      assigns = %{}
      params = %{"name" => "John", "age" => "25"}

      assert {:ok, result} = SimpleActions.run(:simple_action, assigns, params)

      assert result.name == "John"
      # Still a string
      assert result.age_string == "25"
      assert result.raw_params_accessible == true
    end

    test "both raw and cast params are accessible after validation" do
      assigns = %{}
      params = %{"name" => "John", "age" => "25"}

      assert {:ok, result} = SimpleActions.run(:validated_action, assigns, params)

      # Cast params
      assert result.cast_name == "John"
      # Now an integer
      assert result.cast_age == 25

      # Raw params preserved
      assert result.raw_name == "John"
      # Still a string
      assert result.raw_age == "25"

      assert result.both_accessible == true
    end
  end
end
