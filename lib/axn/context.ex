defmodule Axn.Context do
  @moduledoc """
  Context struct that flows through the step pipeline, carrying request data,
  user information, and any step-added fields. Provides helper functions
  similar to `Plug.Conn` and `Phoenix.Component`.
  """

  defstruct [
    :action,        # atom() - Current action name
    assigns: %{},   # map() - Phoenix-style assigns (includes current_user, etc.)
    params: %{},    # map() - Cast and validated parameters
    private: %{},   # map() - Internal DSL state (raw_params, changeset, etc.)
    result: nil     # any() - Action result
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
  Assigns multiple values from a map to the context assigns.
  
  ## Examples
  
      iex> ctx = %Axn.Context{}
      iex> updated_ctx = Axn.Context.assign(ctx, %{current_user: %{id: 123}, theme: "dark"})
      iex> updated_ctx.assigns
      %{current_user: %{id: 123}, theme: "dark"}
  """
  @spec assign(t(), map()) :: t()
  def assign(%__MODULE__{} = ctx, assigns) when is_map(assigns) do
    %{ctx | assigns: Map.merge(ctx.assigns, assigns)}
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

  @doc """
  Merges two contexts, with values from the second context taking precedence.
  Useful for testing.
  
  Note: For assigns and private, maps are merged. For other fields, ctx2 values
  override ctx1 values only if ctx2's value is not nil.
  
  ## Examples
  
      iex> ctx1 = %Axn.Context{action: :action1, assigns: %{user: %{id: 1}}}
      iex> ctx2 = %Axn.Context{assigns: %{theme: "dark"}, result: {:ok, "success"}}
      iex> merged = Axn.Context.merge(ctx1, ctx2)
      iex> merged.action
      :action1
      iex> merged.assigns
      %{user: %{id: 1}, theme: "dark"}
      iex> merged.result
      {:ok, "success"}
  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{} = ctx1, %__MODULE__{} = ctx2) do
    %__MODULE__{
      action: ctx2.action || ctx1.action,
      assigns: Map.merge(ctx1.assigns, ctx2.assigns),
      params: if(ctx2.params == %{}, do: ctx1.params, else: ctx2.params),
      private: Map.merge(ctx1.private, ctx2.private),
      result: ctx2.result || ctx1.result
    }
  end
end