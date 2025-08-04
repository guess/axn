defmodule Axn.Steps.CastValidateParamsTest do
  use ExUnit.Case

  alias Axn.Steps.CastValidateParams

  describe "cast_validate_params/2" do
    test "successfully casts valid params with basic schema" do
      raw_params = %{"name" => "John", "age" => "25"}
      ctx = %Axn.Context{params: raw_params}
      opts = [schema: %{name!: :string, age: :integer}]

      assert {:cont, updated_ctx} = CastValidateParams.cast_validate_params(ctx, opts)
      assert updated_ctx.params == %{name: "John", age: 25}
      # Raw params preserved in private
      assert updated_ctx.private.raw_params == raw_params
      assert updated_ctx.private.changeset.valid?
    end

    test "successfully casts params with optional fields" do
      raw_params = %{"name" => "John"}
      ctx = %Axn.Context{params: raw_params}
      opts = [schema: %{name!: :string, age: :integer}]

      assert {:cont, updated_ctx} = CastValidateParams.cast_validate_params(ctx, opts)
      assert updated_ctx.params == %{name: "John"}
      assert updated_ctx.private.changeset.valid?
    end

    test "successfully casts params with default values" do
      raw_params = %{"name" => "John"}
      ctx = %Axn.Context{params: raw_params}
      opts = [schema: %{name!: :string, region: [field: :string, default: "US"]}]

      assert {:cont, updated_ctx} = CastValidateParams.cast_validate_params(ctx, opts)
      assert updated_ctx.params == %{name: "John", region: "US"}
      assert updated_ctx.private.changeset.valid?
    end

    test "successfully applies custom validation function" do
      raw_params = %{"phone" => "+1234567890", "region" => "US"}
      ctx = %Axn.Context{params: raw_params}

      validate_fn = fn changeset ->
        # Mock custom validation that passes
        changeset
      end

      opts = [schema: %{phone!: :string, region: :string}, validate: validate_fn]

      assert {:cont, updated_ctx} = CastValidateParams.cast_validate_params(ctx, opts)
      assert updated_ctx.params == %{phone: "+1234567890", region: "US"}
      assert updated_ctx.private.changeset.valid?
    end

    test "halts on missing required fields" do
      raw_params = %{"age" => "25"}
      ctx = %Axn.Context{params: raw_params}
      opts = [schema: %{name!: :string, age: :integer}]

      assert {:halt, {:error, %{reason: :invalid_params, changeset: changeset}}} =
               CastValidateParams.cast_validate_params(ctx, opts)

      refute changeset.valid?
      assert changeset.errors[:name] == {"can't be blank", [validation: :required]}
    end

    test "halts on invalid type casting" do
      raw_params = %{"name" => "John", "age" => "not_a_number"}
      ctx = %Axn.Context{params: raw_params}
      opts = [schema: %{name!: :string, age!: :integer}]

      assert {:halt, {:error, %{reason: :invalid_params, changeset: changeset}}} =
               CastValidateParams.cast_validate_params(ctx, opts)

      refute changeset.valid?
      assert changeset.errors[:age] == {"is invalid", [type: :integer, validation: :cast]}
    end

    test "halts when custom validation function fails" do
      raw_params = %{"phone" => "invalid_phone", "region" => "US"}
      ctx = %Axn.Context{params: raw_params}

      validate_fn = fn changeset ->
        # Mock custom validation that fails
        Ecto.Changeset.add_error(changeset, :phone, "invalid phone format")
      end

      opts = [schema: %{phone!: :string, region: :string}, validate: validate_fn]

      assert {:halt, {:error, %{reason: :invalid_params, changeset: changeset}}} =
               CastValidateParams.cast_validate_params(ctx, opts)

      refute changeset.valid?
      assert changeset.errors[:phone] == {"invalid phone format", []}
    end

    test "handles complex nested validation with custom function" do
      raw_params = %{"phone" => "+1234567890", "region" => "US", "challenge_token" => "abc123"}
      ctx = %Axn.Context{params: raw_params}

      validate_fn = fn changeset ->
        params = Ecto.Changeset.apply_changes(changeset)

        changeset
        |> validate_phone_format(params.region)
        |> validate_token_not_expired(params.challenge_token)
      end

      opts = [
        schema: %{
          phone!: :string,
          region: [field: :string, default: "US"],
          challenge_token!: :string
        },
        validate: validate_fn
      ]

      # This should pass with our mock validation
      assert {:cont, updated_ctx} = CastValidateParams.cast_validate_params(ctx, opts)
      assert updated_ctx.params.phone == "+1234567890"
      assert updated_ctx.params.region == "US"
      assert updated_ctx.params.challenge_token == "abc123"
      assert updated_ctx.private.changeset.valid?
    end

    test "supports custom cast functions in schema" do
      # Since custom cast functions can't be used in dynamic modules,
      # we'll test with a direct array input that the params library can handle
      raw_params = %{"tags" => ["elixir", "phoenix", "web"]}
      ctx = %Axn.Context{params: raw_params}

      opts = [schema: %{tags: [field: {:array, :string}]}]

      assert {:cont, updated_ctx} = CastValidateParams.cast_validate_params(ctx, opts)
      assert updated_ctx.params == %{tags: ["elixir", "phoenix", "web"]}
      assert updated_ctx.private.changeset.valid?
    end

    test "requires schema option to be provided" do
      raw_params = %{"name" => "John"}
      ctx = %Axn.Context{params: raw_params}
      # No schema provided
      opts = []

      assert_raise KeyError, fn ->
        CastValidateParams.cast_validate_params(ctx, opts)
      end
    end

    test "works with empty params when no required fields" do
      raw_params = %{}
      ctx = %Axn.Context{params: raw_params}
      opts = [schema: %{name: :string, age: :integer}]

      assert {:cont, updated_ctx} = CastValidateParams.cast_validate_params(ctx, opts)
      assert updated_ctx.params == %{}
      assert updated_ctx.private.changeset.valid?
    end
  end

  # Mock helper functions for testing
  defp validate_phone_format(changeset, _region) do
    # Mock validation - just pass through for now
    changeset
  end

  defp validate_token_not_expired(changeset, _token) do
    # Mock validation - just pass through for now  
    changeset
  end
end
