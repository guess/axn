defmodule Axn.Steps.CastValidateParams do
  @moduledoc """
  Built-in step for casting and validating parameters with schema validation and optional custom validation.

  This step takes raw parameters from the context, casts them according to a schema,
  and optionally applies custom validation logic.
  """

  import Axn.Context

  def cast_validate_params(%Axn.Context{} = ctx, opts) do
    schema = Keyword.fetch!(opts, :schema)
    validate_fn = Keyword.get(opts, :validate)
    raw_params = get_private(ctx, :raw_params)

    case cast_and_validate_params(raw_params, schema, validate_fn) do
      {:ok, params, changeset} ->
        new_ctx =
          ctx
          |> put_params(params)
          |> put_private(:changeset, changeset)

        {:cont, new_ctx}

      {:error, changeset} ->
        {:halt, {:error, %{reason: :invalid_params, changeset: changeset}}}
    end
  end

  defp cast_and_validate_params(raw_params, schema, validate_fn) do
    # Create a dynamic module using the params library
    dynamic_module = create_dynamic_params_module(schema)

    # Create changeset using the dynamic module
    changeset = dynamic_module.from(raw_params)

    # Apply custom validation function if provided
    final_changeset =
      if validate_fn do
        validate_fn.(changeset)
      else
        changeset
      end

    if final_changeset.valid? do
      params = Params.to_map(final_changeset)
      {:ok, params, final_changeset}
    else
      {:error, final_changeset}
    end
  end

  defp create_dynamic_params_module(schema) do
    # Convert our schema format to params format
    # params_schema = convert_schema_format(schema)

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
