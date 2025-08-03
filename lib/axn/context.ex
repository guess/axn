defmodule Axn.Context do
  @moduledoc """
  Context struct that flows through the step pipeline, carrying request data,
  user information, and any step-added fields. Provides helper functions
  similar to `Plug.Conn` and `Phoenix.Component`.
  """

  defstruct [
    # atom() - Current action name
    :action,
    # map() - Phoenix-style assigns (includes current_user, etc.)
    assigns: %{},
    # map() - Cast and validated parameters
    params: %{},
    # map() - Internal DSL state (raw_params, changeset, etc.)
    private: %{},
    # any() - Action result
    result: nil
  ]

  @type t :: %__MODULE__{
          action: atom() | nil,
          assigns: map(),
          params: map(),
          private: map(),
          result: any()
        }

  @doc """
  Assigns a value to a key in the context assigns.

  ## Examples

      iex> ctx = %Axn.Context{}
      iex> updated_ctx = Axn.Context.assign(ctx, :current_user, %{id: 123})
      iex> updated_ctx.assigns
      %{current_user: %{id: 123}}
  """
  @spec assign(t(), atom(), any()) :: t()
  def assign(%__MODULE__{} = ctx, key, value) when is_atom(key) do
    %{ctx | assigns: Map.put(ctx.assigns, key, value)}
  end

  @doc """
  Assigns multiple values from a map or keyword list to the context assigns.

  ## Examples

      iex> ctx = %Axn.Context{}
      iex> updated_ctx = Axn.Context.assign(ctx, %{current_user: %{id: 123}, theme: "dark"})
      iex> updated_ctx.assigns
      %{current_user: %{id: 123}, theme: "dark"}

      iex> ctx = %Axn.Context{}
      iex> updated_ctx = Axn.Context.assign(ctx, current_user: %{id: 123}, theme: "dark")
      iex> updated_ctx.assigns
      %{current_user: %{id: 123}, theme: "dark"}
  """
  @spec assign(t(), map() | keyword()) :: t()
  def assign(%__MODULE__{} = ctx, assigns) when is_map(assigns) do
    %{ctx | assigns: Map.merge(ctx.assigns, assigns)}
  end

  def assign(%__MODULE__{} = ctx, assigns) when is_list(assigns) do
    assign(ctx, Enum.into(assigns, %{}))
  end

  @doc """
  Gets a value from the private storage of the context.

  ## Examples

      iex> ctx = %Axn.Context{private: %{correlation_id: "abc123"}}
      iex> Axn.Context.get_private(ctx, :correlation_id)
      "abc123"

      iex> ctx = %Axn.Context{}
      iex> Axn.Context.get_private(ctx, :non_existent)
      nil
  """
  @spec get_private(t(), atom()) :: any()
  def get_private(%__MODULE__{} = ctx, key) when is_atom(key) do
    Map.get(ctx.private, key)
  end

  @doc """
  Gets a value from the private storage of the context with a default.

  ## Examples

      iex> ctx = %Axn.Context{private: %{correlation_id: "abc123"}}
      iex> Axn.Context.get_private(ctx, :correlation_id, "default")
      "abc123"

      iex> ctx = %Axn.Context{}
      iex> Axn.Context.get_private(ctx, :non_existent, "my_default")
      "my_default"
  """
  @spec get_private(t(), atom(), any()) :: any()
  def get_private(%__MODULE__{} = ctx, key, default) when is_atom(key) do
    Map.get(ctx.private, key, default)
  end

  @doc """
  Puts a value in the private storage of the context.

  ## Examples

      iex> ctx = %Axn.Context{}
      iex> updated_ctx = Axn.Context.put_private(ctx, :correlation_id, "abc123")
      iex> updated_ctx.private
      %{correlation_id: "abc123"}
  """
  @spec put_private(t(), atom(), any()) :: t()
  def put_private(%__MODULE__{} = ctx, key, value) when is_atom(key) do
    %{ctx | private: Map.put(ctx.private, key, value)}
  end

  @doc """
  Updates the params in the context.

  ## Examples

      iex> ctx = %Axn.Context{}
      iex> updated_ctx = Axn.Context.put_params(ctx, %{name: "John", age: 25})
      iex> updated_ctx.params
      %{name: "John", age: 25}
  """
  @spec put_params(t(), map()) :: t()
  def put_params(%__MODULE__{} = ctx, params) when is_map(params) do
    %{ctx | params: params}
  end

  @doc """
  Updates the result in the context.

  ## Examples

      iex> ctx = %Axn.Context{}
      iex> updated_ctx = Axn.Context.put_result(ctx, {:ok, %{id: 123}})
      iex> updated_ctx.result
      {:ok, %{id: 123}}
  """
  @spec put_result(t(), any()) :: t()
  def put_result(%__MODULE__{} = ctx, result) do
    %{ctx | result: result}
  end
end
