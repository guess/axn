defmodule Axn.TestHelpers do
  @moduledoc """
  Test helpers for testing Axn actions and steps in downstream applications.

  These helpers make it easy to:
  - Create test contexts with realistic data
  - Test individual steps in isolation
  - Set up telemetry capture for testing
  - Assert on common step behaviors

  ## Usage

      defmodule MyApp.UserActionsTest do
        use ExUnit.Case
        import Axn.TestHelpers
        
        test "my step works correctly" do
          ctx = build_context(
            params: %{email: "test@example.com"},
            assigns: %{current_user: build_user()}
          )
          
          assert {:cont, updated_ctx} = MyStep.validate_email(ctx)
          assert updated_ctx.assigns.email_valid == true
        end
      end
  """

  import ExUnit.Assertions

  alias Axn.Context

  @doc """
  Creates a basic context for testing with commonly used defaults.

  ## Options

  - `:action` - The action name (default: `:test_action`)
  - `:assigns` - Map of assigns (default: `%{}`)
  - `:params` - Map of validated parameters (default: `%{}`)
  - `:raw_params` - Map of raw parameters (default: same as `:params`)
  - `:private` - Map of private data (default: `%{}`)
  - `:result` - Action result (default: `nil`)

  ## Examples

      # Basic context
      ctx = build_context()
      
      # With params and user
      ctx = build_context(
        params: %{email: "test@example.com"}, 
        assigns: %{current_user: %{id: 123}}
      )
      
      # With raw params different from cast params
      ctx = build_context(
        params: %{age: 25},
        raw_params: %{"age" => "25"}
      )
  """
  def build_context(opts \\ []) do
    action = Keyword.get(opts, :action, :test_action)
    assigns = Keyword.get(opts, :assigns, %{})
    params = Keyword.get(opts, :params, %{})
    raw_params = Keyword.get(opts, :raw_params, params)
    private = Keyword.get(opts, :private, %{raw_params: raw_params})
    result = Keyword.get(opts, :result)

    %Context{
      action: action,
      assigns: assigns,
      params: params,
      private: private,
      result: result
    }
  end

  @doc """
  Creates a test user with common attributes for testing authorization.

  ## Options

  - `:id` - User ID (default: random integer)
  - `:role` - User role (default: "user")
  - `:email` - User email (default: "test@example.com")
  - Additional attributes can be passed and will be included

  ## Examples

      user = build_user()
      admin = build_user(role: "admin")
      specific_user = build_user(id: 123, email: "admin@example.com")
  """
  def build_user(opts \\ []) do
    id = Keyword.get(opts, :id, :rand.uniform(10_000))
    role = Keyword.get(opts, :role, "user")
    email = Keyword.get(opts, :email, "test@example.com")

    base = %{id: id, role: role, email: email}

    # Add any additional attributes
    additional_attrs = Keyword.drop(opts, [:id, :role, :email])

    Enum.reduce(additional_attrs, base, fn {key, value}, acc ->
      Map.put(acc, key, value)
    end)
  end

  @doc """
  Creates a changeset for testing parameter validation failures.

  ## Examples

      # Valid changeset
      changeset = build_changeset(%{email: "test@example.com"})
      
      # Invalid changeset with errors
      changeset = build_changeset(%{}, [email: "can't be blank"])
  """
  def build_changeset(params, errors \\ []) do
    types = %{email: :string, name: :string, age: :integer}

    changeset = Ecto.Changeset.cast({%{}, types}, params, Map.keys(types))

    # Add errors if provided
    Enum.reduce(errors, changeset, fn {field, message}, acc ->
      Ecto.Changeset.add_error(acc, field, message)
    end)
  end

  @doc """
  Captures telemetry events during test execution.

  Returns a function that when called returns all captured events.
  Automatically detaches telemetry handlers after the test.

  ## Examples

      test "action emits telemetry" do
        events = capture_telemetry([:my_app, :users])
        
        MyActions.run(:create_user, %{}, %{})
        
        captured_events = events.()
        assert length(captured_events) == 2  # start and stop
      end
  """
  def capture_telemetry(event_prefixes) when is_list(event_prefixes) do
    test_pid = self()
    handler_id = "test-#{:rand.uniform(10_000)}"

    # Create all event patterns (start/stop for each prefix)
    events =
      Enum.flat_map(event_prefixes, fn prefix ->
        [prefix ++ [:start], prefix ++ [:stop]]
      end)

    :telemetry.attach_many(
      handler_id,
      events,
      &__MODULE__.handle_telemetry_event/4,
      test_pid
    )

    # Return a function to get captured events and clean up
    fn ->
      :telemetry.detach(handler_id)
      collect_telemetry_messages([])
    end
  end

  def capture_telemetry(event_prefix) when is_list(event_prefix) do
    capture_telemetry([event_prefix])
  end

  @doc false
  def handle_telemetry_event(event, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry_event, event, measurements, metadata})
  end

  defp collect_telemetry_messages(acc) do
    receive do
      {:telemetry_event, event, measurements, metadata} ->
        collect_telemetry_messages([{event, measurements, metadata} | acc])
    after
      10 -> Enum.reverse(acc)
    end
  end

  @doc """
  Asserts that a step returns `{:cont, context}` and the context matches expectations.

  ## Examples

      assert_step_continues(result, fn ctx ->
        assert ctx.params.email == "test@example.com"
        assert ctx.assigns.validated == true
      end)
  """
  def assert_step_continues({:cont, ctx}, assertion_fn) do
    assertion_fn.(ctx)
    {:cont, ctx}
  end

  def assert_step_continues(other, _assertion_fn) do
    flunk("Expected {:cont, context}, got: #{inspect(other)}")
  end

  @doc """
  Asserts that a step returns `{:halt, result}` and the result matches expectations.

  ## Examples

      assert_step_halts(result, {:ok, user}, fn user ->
        assert user.id
        assert user.email == "test@example.com"
      end)
      
      assert_step_halts(result, {:error, :unauthorized})
  """
  def assert_step_halts(step_result, expected_result, assertion_fn \\ nil)

  def assert_step_halts({:halt, result}, expected_result, assertion_fn) do
    assert result == expected_result

    if assertion_fn && match?({:ok, _value}, result) do
      {:ok, value} = result
      assertion_fn.(value)
    end

    {:halt, result}
  end

  def assert_step_halts(other, expected_result, _assertion_fn) do
    flunk("Expected {:halt, #{inspect(expected_result)}}, got: #{inspect(other)}")
  end

  @doc """
  Asserts that an action run returns `{:ok, result}` and the result matches expectations.

  ## Examples

      assert_action_succeeds(
        MyActions.run(:create_user, assigns, params),
        fn user ->
          assert user.id
          assert user.email == "test@example.com"
        end
      )
  """
  def assert_action_succeeds({:ok, result}, assertion_fn) do
    assertion_fn.(result)
    {:ok, result}
  end

  def assert_action_succeeds(other, _assertion_fn) do
    flunk("Expected {:ok, result}, got: #{inspect(other)}")
  end

  @doc """
  Asserts that an action run returns `{:error, reason}` and optionally checks the reason.

  ## Examples

      assert_action_fails(MyActions.run(:create_user, assigns, params), :unauthorized)
      
      assert_action_fails(
        MyActions.run(:create_user, assigns, params),
        %{reason: :invalid_params},
        fn error ->
          assert error.changeset
          refute error.changeset.valid?
        end
      )
  """
  def assert_action_fails(action_result, expected_reason, assertion_fn \\ nil)

  def assert_action_fails({:error, reason}, expected_reason, assertion_fn) do
    assert reason == expected_reason

    if assertion_fn do
      assertion_fn.(reason)
    end

    {:error, reason}
  end

  def assert_action_fails(other, expected_reason, _assertion_fn) do
    flunk("Expected {:error, #{inspect(expected_reason)}}, got: #{inspect(other)}")
  end

  @doc """
  Creates a mock step function for testing step pipelines.

  ## Examples

      # Step that always continues
      step_fn = mock_step(:cont, fn ctx -> 
        Context.assign(ctx, :processed, true) 
      end)
      
      # Step that halts with success
      step_fn = mock_step(:halt, {:ok, %{result: "success"}})
      
      # Step that halts with error
      step_fn = mock_step(:halt, {:error, :validation_failed})
  """
  def mock_step(:cont, ctx_transformer) when is_function(ctx_transformer, 1) do
    fn ctx -> {:cont, ctx_transformer.(ctx)} end
  end

  def mock_step(:cont, ctx_transformer) when is_function(ctx_transformer, 2) do
    fn ctx, opts -> {:cont, ctx_transformer.(ctx, opts)} end
  end

  def mock_step(:halt, result) when is_function(result, 1) do
    fn ctx -> {:halt, result.(ctx)} end
  end

  def mock_step(:halt, result) do
    fn _ctx -> {:halt, result} end
  end

  @doc """
  Runs a step pipeline manually for testing complex step interactions.

  ## Examples

      steps = [
        {:cast_validate_params, [schema: %{email!: :string}]},
        {:my_custom_step, []},
        {:finalize, []}
      ]
      
      ctx = build_context(raw_params: %{"email" => "test@example.com"})
      final_ctx = run_step_pipeline(steps, ctx, MyModule)
      
      assert final_ctx.result == {:ok, "success"}
  """
  def run_step_pipeline(steps, initial_ctx, module) do
    Enum.reduce_while(steps, initial_ctx, fn {step_name, opts}, ctx ->
      case apply(module, :apply_step, [step_name, ctx, opts]) do
        {:cont, new_ctx} -> {:cont, new_ctx}
        {:halt, result} -> {:halt, Context.put_result(ctx, result)}
      end
    end)
  end
end
