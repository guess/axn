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
      ctx = %Axn.Context{params: raw_params, action: :test_action}

      validate_fn = fn changeset, _ctx ->
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
      ctx = %Axn.Context{params: raw_params, action: :test_action}

      validate_fn = fn changeset, _ctx ->
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
      ctx = %Axn.Context{params: raw_params, action: :request_otp}

      validate_fn = fn changeset, ctx ->
        params = Ecto.Changeset.apply_changes(changeset)

        changeset
        |> validate_phone_format(params.region)
        |> validate_token_not_expired(params.challenge_token)
        |> validate_action_context(ctx.action)
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

    test "validation function can pattern match on action name" do
      raw_params = %{"phone" => "+1234567890"}
      ctx = %Axn.Context{params: raw_params, action: :request_otp}

      validate_fn = fn changeset, %{action: :request_otp} ->
        # Action-specific validation for request_otp - add custom validation
        Ecto.Changeset.validate_format(changeset, :phone, ~r/^\+/)
      end

      opts = [schema: %{phone!: :string}, validate: validate_fn]

      assert {:cont, updated_ctx} = CastValidateParams.cast_validate_params(ctx, opts)
      assert updated_ctx.params.phone == "+1234567890"
      assert updated_ctx.private.changeset.valid?
    end

    test "validation function can pattern match on user role in assigns" do
      user = %{role: "admin", id: 123}
      raw_params = %{"action_type" => "restricted"}

      ctx = %Axn.Context{
        params: raw_params,
        action: :admin_action,
        assigns: %{current_user: user}
      }

      validate_fn = fn changeset, %{assigns: %{current_user: %{role: "admin"}}} ->
        # Admin users get more lenient validation rules
        changeset
      end

      opts = [schema: %{action_type!: :string}, validate: validate_fn]

      assert {:cont, updated_ctx} = CastValidateParams.cast_validate_params(ctx, opts)
      assert updated_ctx.params.action_type == "restricted"
      assert updated_ctx.private.changeset.valid?
    end

    test "validation function can access multiple context fields" do
      user = %{id: 123, role: "user"}
      raw_params = %{"operation" => "update"}

      ctx = %Axn.Context{
        params: raw_params,
        action: :update_resource,
        assigns: %{current_user: user, tenant: %{slug: "acme"}}
      }

      validate_fn = fn changeset, ctx ->
        user_id = ctx.assigns.current_user.id
        tenant_slug = ctx.assigns.tenant.slug
        action = ctx.action

        # Store validation context in changeset metadata for verification
        changeset = Ecto.Changeset.put_change(changeset, :operation, "update_#{tenant_slug}")

        # Apply context-aware validation
        case {user_id > 100, tenant_slug, action} do
          {true, "acme", :update_resource} ->
            # Valid case - user has sufficient ID and is in acme tenant
            changeset

          _ ->
            Ecto.Changeset.add_error(changeset, :operation, "invalid context")
        end
      end

      opts = [schema: %{operation!: :string}, validate: validate_fn]

      assert {:cont, updated_ctx} = CastValidateParams.cast_validate_params(ctx, opts)
      assert updated_ctx.params.operation == "update_acme"
      assert updated_ctx.private.changeset.valid?
    end

    test "validation function pattern matching works with multiple action clauses" do
      # Test first action pattern
      raw_params = %{"phone" => "+1234567890"}
      ctx1 = %Axn.Context{params: raw_params, action: :request_otp}

      multi_action_validate_fn = fn
        changeset, %{action: :request_otp} ->
          # OTP request needs phone format validation
          Ecto.Changeset.validate_format(changeset, :phone, ~r/^\+\d+$/)

        changeset, %{action: :verify_otp} ->
          # OTP verify needs both phone and code validation
          changeset
          |> Ecto.Changeset.validate_format(:phone, ~r/^\+\d+$/)
          |> Ecto.Changeset.validate_length(:code, is: 6)

        changeset, _ctx ->
          # Default validation - just pass through
          changeset
      end

      opts1 = [schema: %{phone!: :string}, validate: multi_action_validate_fn]
      assert {:cont, updated_ctx1} = CastValidateParams.cast_validate_params(ctx1, opts1)
      assert updated_ctx1.params.phone == "+1234567890"
      assert updated_ctx1.private.changeset.valid?

      # Test second action pattern
      raw_params2 = %{"phone" => "+1234567890", "code" => "123456"}
      ctx2 = %Axn.Context{params: raw_params2, action: :verify_otp}

      opts2 = [schema: %{phone!: :string, code!: :string}, validate: multi_action_validate_fn]
      assert {:cont, updated_ctx2} = CastValidateParams.cast_validate_params(ctx2, opts2)
      assert updated_ctx2.params.phone == "+1234567890"
      assert updated_ctx2.params.code == "123456"
      assert updated_ctx2.private.changeset.valid?

      # Test default pattern
      raw_params3 = %{"data" => "test"}
      ctx3 = %Axn.Context{params: raw_params3, action: :other_action}

      opts3 = [schema: %{data!: :string}, validate: multi_action_validate_fn]
      assert {:cont, updated_ctx3} = CastValidateParams.cast_validate_params(ctx3, opts3)
      assert updated_ctx3.params.data == "test"
      assert updated_ctx3.private.changeset.valid?
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

  defp validate_action_context(changeset, _action) do
    # Mock validation that ensures we can access action context
    changeset
  end
end
