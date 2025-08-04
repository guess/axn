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
    # Create a simple changeset for casting and validation
    changeset = create_changeset(%{}, raw_params, schema)

    # Apply custom validation function if provided
    final_changeset =
      if validate_fn do
        validate_fn.(changeset)
      else
        changeset
      end

    if final_changeset.valid? do
      params = Ecto.Changeset.apply_changes(final_changeset)
      {:ok, params, final_changeset}
    else
      {:error, final_changeset}
    end
  end

  defp create_changeset(data, params, schema) do
    import Ecto.Changeset

    types = build_types(schema)
    required_fields = extract_required_fields(schema)
    optional_fields = extract_optional_fields(schema)

    {data, types}
    |> cast(params, required_fields ++ optional_fields)
    |> validate_required(required_fields)
    |> apply_defaults(schema)
  end

  defp build_types(schema) do
    Enum.into(schema, %{}, fn
      {field_name, type} when is_atom(type) ->
        field_name = if is_binary(field_name), do: String.to_atom(field_name), else: field_name
        clean_field = String.replace(to_string(field_name), "!", "")
        {String.to_atom(clean_field), type}

      {field_name, options} when is_list(options) ->
        field_name = if is_binary(field_name), do: String.to_atom(field_name), else: field_name
        clean_field = String.replace(to_string(field_name), "!", "")
        type = Keyword.get(options, :field)
        {String.to_atom(clean_field), type}
    end)
  end

  defp extract_required_fields(schema) do
    schema
    |> Enum.filter(fn
      {field_name, _type} when is_atom(field_name) ->
        String.ends_with?(to_string(field_name), "!")

      {field_name, _type} when is_binary(field_name) ->
        String.ends_with?(field_name, "!")
    end)
    |> Enum.map(fn {field_name, _type} ->
      field_name = if is_binary(field_name), do: String.to_atom(field_name), else: field_name
      clean_field = String.replace(to_string(field_name), "!", "")
      String.to_atom(clean_field)
    end)
  end

  defp extract_optional_fields(schema) do
    schema
    |> Enum.reject(fn
      {field_name, _type} when is_atom(field_name) ->
        String.ends_with?(to_string(field_name), "!")

      {field_name, _type} when is_binary(field_name) ->
        String.ends_with?(field_name, "!")
    end)
    |> Enum.map(fn {field_name, _type} ->
      field_name = if is_binary(field_name), do: String.to_atom(field_name), else: field_name
      String.to_atom(to_string(field_name))
    end)
  end

  defp apply_defaults(changeset, schema) do
    Enum.reduce(schema, changeset, fn
      {field_name, [field: _type, default: default_value]}, acc ->
        field_name = if is_binary(field_name), do: String.to_atom(field_name), else: field_name
        clean_field = String.replace(to_string(field_name), "!", "")
        field_atom = String.to_atom(clean_field)

        if Ecto.Changeset.get_field(acc, field_atom) == nil do
          Ecto.Changeset.put_change(acc, field_atom, default_value)
        else
          acc
        end

      _other, acc ->
        acc
    end)
  end
end
