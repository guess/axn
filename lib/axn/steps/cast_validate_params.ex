defmodule Axn.Steps.CastValidateParams do
  @moduledoc """
  Built-in step for casting and validating parameters with schema validation and optional custom validation.

  This step takes raw parameters from the context, casts them according to a schema,
  and optionally applies custom validation logic.
  """

  import Axn.Context

  @type validate_fun :: (Ecto.Changeset.t() -> Ecto.Changeset.t())

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

  defp apply_validate_fun(changeset, validate_fn) when is_function(validate_fn) do
    validate_fn.(changeset)
  end

  defp apply_validate_fun(changeset, _validate_fn) do
    changeset
  end

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
