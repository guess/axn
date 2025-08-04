defmodule Axn.Steps.CastValidateParams do
  @moduledoc """
  Built-in step for casting and validating parameters with schema validation and optional custom validation.

  This step takes raw parameters from the context, casts them according to a schema,
  and optionally applies custom validation logic.
  """

  import Axn.Context

  @type validate_fun :: (Ecto.Changeset.t() -> Ecto.Changeset.t())

  @doc """
  Casts and validates parameters according to a schema with optional custom validation.

  This step takes raw parameters from the context, casts them according to a schema,
  and optionally applies custom validation logic. The schema uses the `Params` library
  format and supports required fields, optional fields, defaults, and custom validation.

  ## Options

  * `:schema` - Parameter schema map (required). Uses `Params.Schema` format.
  * `:validate` - Custom validation function that receives changeset (optional).

  ## Schema Format

  The schema follows the `Params.Schema` format:

  * `field!: :type` - Required field of the specified type
  * `field: :type` - Optional field of the specified type  
  * `field: [field: :type, default: value]` - Field with default value
  * `field: [field: :type, cast: &func/1]` - Field with custom cast function

  Supported types include `:string`, `:integer`, `:boolean`, `:atom`, `:map`, `:list`, etc.

  ## Custom Validation

  The optional `:validate` function receives an `Ecto.Changeset` after initial casting
  and validation. It should return a modified changeset with any additional validations
  applied:

      validate_fn = fn changeset ->
        changeset
        |> validate_format(:email, ~r/@/)
        |> validate_length(:name, min: 2)
      end

  ## Context Updates

  On success, this step updates the context:
  - `ctx.params` - Contains the cast and validated parameters
  - `ctx.private.raw_params` - Contains the original raw parameters
  - `ctx.private.changeset` - Contains the final changeset

  ## Examples

      # Basic schema validation
      step :cast_validate_params, schema: %{
        email!: :string,
        name: :string,
        age: [field: :integer, default: 18]
      }

      # With custom validation
      step :cast_validate_params,
           schema: %{phone!: :string, region: [field: :string, default: "US"]},
           validate: &validate_phone_number/1

      defp validate_phone_number(changeset) do
        params = Params.to_map(changeset)
        validate_format(changeset, :phone, phone_regex_for_region(params.region))
      end

  ## Returns

  * `{:cont, updated_context}` - Parameters are valid, pipeline continues
  * `{:halt, {:error, %{reason: :invalid_params, changeset: changeset}}}` - Validation failed

  The error changeset contains all validation errors and can be used to generate
  user-friendly error messages.
  """
  @spec cast_validate_params(Axn.Context.t(), keyword()) ::
          {:cont, Axn.Context.t()} | {:halt, {:error, map()}}
  def cast_validate_params(%Axn.Context{} = ctx, opts) do
    schema = Keyword.fetch!(opts, :schema)
    validate_fn = Keyword.get(opts, :validate)
    raw_params = ctx.params
    changeset = handle_cast_params(raw_params, schema)

    case handle_validate_params(changeset, validate_fn) do
      {:ok, params, changeset} ->
        new_ctx =
          ctx
          # Preserve raw params in private
          |> put_private(:raw_params, raw_params)
          # Replace with cast params
          |> put_params(params)
          |> put_private(:changeset, changeset)

        {:cont, new_ctx}

      {:error, changeset} ->
        {:halt, {:error, %{reason: :invalid_params, changeset: changeset}}}
    end
  end

  @spec handle_cast_params(map(), map()) :: Ecto.Changeset.t()
  defp handle_cast_params(raw_params, schema) do
    # Create a dynamic module using the params library
    dynamic_module = create_dynamic_params_module(schema)

    # Create changeset using the dynamic module
    dynamic_module.from(raw_params)
  end

  @spec handle_validate_params(Ecto.Changeset.t(), validate_fun() | nil) ::
          {:ok, map(), Ecto.Changeset.t()} | {:error, Ecto.Changeset.t()}
  defp handle_validate_params(changeset, validate_fn) do
    changeset
    |> apply_validate_fun(validate_fn)
    |> case do
      %{valid?: true} = changeset ->
        params = Params.to_map(changeset)
        {:ok, params, changeset}

      changeset ->
        {:error, changeset}
    end
  end

  @spec apply_validate_fun(Ecto.Changeset.t(), validate_fun() | nil) :: Ecto.Changeset.t()
  defp apply_validate_fun(changeset, validate_fn) when is_function(validate_fn) do
    validate_fn.(changeset)
  end

  defp apply_validate_fun(changeset, _validate_fn) do
    changeset
  end

  @spec create_dynamic_params_module(map()) :: atom()
  defp create_dynamic_params_module(schema) do
    # Create a unique module name to avoid conflicts
    module_name = :"DynamicParamsModule#{:erlang.unique_integer([:positive])}"

    # Generate the module code
    module_code =
      quote do
        defmodule unquote(module_name) do
          use Params.Schema, unquote(Macro.escape(schema))
        end
      end

    # Compile and load the module
    Code.eval_quoted(module_code, [], __ENV__)

    module_name
  end
end
