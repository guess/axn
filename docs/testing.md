# Testing Guide

Axn provides comprehensive testing patterns and helpers to make testing actions and steps straightforward. This guide covers testing individual steps, full actions, and telemetry integration.

## Testing Actions

### Basic Action Testing

Test actions using the standard `run/3` function:

```elixir
defmodule MyApp.UserActionsTest do
  use ExUnit.Case
  
  test "create_user succeeds with valid input" do
    assigns = %{current_user: %User{id: 123, role: "admin"}}
    params = %{"email" => "test@example.com", "name" => "John Doe"}
    
    assert {:ok, user} = MyApp.UserActions.run(:create_user, params, assigns)
    assert user.email == "test@example.com"
    assert user.name == "John Doe"
  end
  
  test "create_user fails with invalid params" do
    assigns = %{current_user: %User{id: 123, role: "admin"}}
    params = %{"email" => "invalid-email", "name" => ""}
    
    assert {:error, %{reason: :invalid_params, changeset: changeset}} = 
           MyApp.UserActions.run(:create_user, params, assigns)
    
    refute changeset.valid?
    assert changeset.errors[:email]
    assert changeset.errors[:name]
  end
  
  test "create_user fails authorization" do
    assigns = %{current_user: %User{id: 123, role: "user"}}  # Not admin
    params = %{"email" => "test@example.com", "name" => "John Doe"}
    
    assert {:error, :unauthorized} = MyApp.UserActions.run(:create_user, params, assigns)
  end
end
```

### Testing with Different Sources

Test how actions work with different Phoenix contexts:

```elixir
test "action works with Phoenix conn" do
  conn = %Plug.Conn{assigns: %{current_user: build_user(role: "admin")}}
  params = %{"email" => "test@example.com", "name" => "John"}
  
  assert {:ok, user} = MyApp.UserActions.run(:create_user, params, conn)
  assert user.email == "test@example.com"
end

test "action works with LiveView socket" do
  socket = %Phoenix.LiveView.Socket{assigns: %{current_user: build_user(role: "admin")}}
  params = %{"email" => "test@example.com", "name" => "John"}
  
  assert {:ok, user} = MyApp.UserActions.run(:create_user, params, socket)
  assert user.email == "test@example.com"
end

test "action works with plain assigns map" do
  assigns = %{current_user: build_user(role: "admin")}
  params = %{"email" => "test@example.com", "name" => "John"}
  
  assert {:ok, user} = MyApp.UserActions.run(:create_user, params, assigns)
  assert user.email == "test@example.com"
end
```

## Testing Individual Steps

### Unit Testing Steps

Steps are pure functions, making them easy to unit test:

```elixir
defmodule MyApp.UserActions.StepsTest do
  use ExUnit.Case
  alias Axn.Context
  
  describe "require_admin/1" do
    test "continues when user is admin" do
      ctx = %Context{
        action: :create_user,
        assigns: %{current_user: %User{role: "admin"}},
        params: %{},
        private: %{},
        result: nil
      }
      
      assert {:cont, ^ctx} = MyApp.UserActions.require_admin(ctx)
    end
    
    test "halts when user is not admin" do
      ctx = %Context{
        action: :create_user,
        assigns: %{current_user: %User{role: "user"}},
        params: %{},
        private: %{},
        result: nil
      }
      
      assert {:halt, {:error, :unauthorized}} = MyApp.UserActions.require_admin(ctx)
    end
    
    test "halts when no user present" do
      ctx = %Context{
        action: :create_user,
        assigns: %{},
        params: %{},
        private: %{},
        result: nil
      }
      
      assert {:halt, {:error, :unauthorized}} = MyApp.UserActions.require_admin(ctx)
    end
  end
  
  describe "validate_user_params/1" do
    test "continues with valid params" do
      ctx = %Context{
        action: :create_user,
        assigns: %{},
        params: %{"email" => "test@example.com", "name" => "John"},
        private: %{},
        result: nil
      }
      
      assert {:cont, updated_ctx} = MyApp.UserActions.validate_user_params(ctx)
      assert updated_ctx.params.email == "test@example.com"
      assert updated_ctx.params.name == "John"
    end
    
    test "halts with invalid params" do
      ctx = %Context{
        action: :create_user,
        assigns: %{},
        params: %{"email" => "invalid", "name" => ""},
        private: %{},
        result: nil
      }
      
      assert {:halt, {:error, %{reason: :invalid_params, changeset: changeset}}} = 
             MyApp.UserActions.validate_user_params(ctx)
      
      refute changeset.valid?
    end
  end
end
```

### Testing External Steps

```elixir
defmodule MyStepsTest do
  use ExUnit.Case
  alias Axn.Context
  
  describe "enrich_context/2" do
    test "enriches context with user preferences" do
      user = %User{id: 123}
      ctx = %Context{
        assigns: %{current_user: user},
        params: %{},
        private: %{},
        result: nil
      }
      
      assert {:cont, enriched_ctx} = MySteps.enrich_context(ctx, fields: [:preferences])
      assert enriched_ctx.assigns.user_preferences
      assert enriched_ctx.assigns.enriched == true
    end
    
    test "handles missing user gracefully" do
      ctx = %Context{
        assigns: %{},
        params: %{},
        private: %{},
        result: nil
      }
      
      assert {:cont, enriched_ctx} = MySteps.enrich_context(ctx, fields: [:preferences])
      assert enriched_ctx.assigns.user_preferences == nil
    end
  end
end
```

## Test Helpers

### Building Test Contexts

Create helper functions to build test contexts quickly:

```elixir
defmodule MyApp.TestHelpers do
  alias Axn.Context
  
  def build_context(opts \\ []) do
    %Context{
      action: opts[:action] || :test_action,
      assigns: opts[:assigns] || %{},
      params: opts[:params] || %{},
      private: opts[:private] || %{},
      result: opts[:result]
    }
  end
  
  def build_user_context(user, opts \\ []) do
    assigns = Map.merge(%{current_user: user}, opts[:assigns] || %{})
    build_context(Keyword.put(opts, :assigns, assigns))
  end
  
  def build_admin_context(opts \\ []) do
    user = build_user(role: "admin")
    build_user_context(user, opts)
  end
  
  def build_user(attrs \\ []) do
    %User{
      id: attrs[:id] || :rand.uniform(1000),
      email: attrs[:email] || "user#{:rand.uniform(1000)}@example.com",
      name: attrs[:name] || "Test User",
      role: attrs[:role] || "user"
    }
  end
  
  def build_tenant(attrs \\ []) do
    %Tenant{
      id: attrs[:id] || :rand.uniform(1000),
      slug: attrs[:slug] || "tenant#{:rand.uniform(1000)}",
      name: attrs[:name] || "Test Tenant"
    }
  end
end
```

### Action Test Helpers

Create helpers for common action testing patterns:

```elixir
defmodule MyApp.ActionTestHelpers do
  def assert_action_succeeds(action_result, assertion_fn \\ nil) do
    case action_result do
      {:ok, result} ->
        if assertion_fn, do: assertion_fn.(result)
        result
      {:error, reason} ->
        flunk("Expected action to succeed, but got error: #{inspect(reason)}")
    end
  end
  
  def assert_action_fails(action_result, expected_reason \\ nil) do
    case action_result do
      {:error, reason} ->
        if expected_reason do
          assert reason == expected_reason, 
                 "Expected error #{inspect(expected_reason)}, got #{inspect(reason)}"
        end
        reason
      {:ok, result} ->
        flunk("Expected action to fail, but got success: #{inspect(result)}")
    end
  end
  
  def assert_step_continues(step_result, assertion_fn \\ nil) do
    case step_result do
      {:cont, ctx} ->
        if assertion_fn, do: assertion_fn.(ctx)
        ctx
      {:halt, result} ->
        flunk("Expected step to continue, but got halt: #{inspect(result)}")
    end
  end
  
  def assert_step_halts(step_result, expected_result \\ nil) do
    case step_result do
      {:halt, result} ->
        if expected_result do
          assert result == expected_result,
                 "Expected halt with #{inspect(expected_result)}, got #{inspect(result)}"
        end
        result
      {:cont, ctx} ->
        flunk("Expected step to halt, but got continue: #{inspect(ctx)}")
    end
  end
end
```

### Usage with Helpers

```elixir
defmodule MyApp.UserActionsTest do
  use ExUnit.Case
  import MyApp.TestHelpers
  import MyApp.ActionTestHelpers
  
  test "create_user with helpers" do
    user = build_user(role: "admin") 
    params = %{"email" => "test@example.com", "name" => "John"}
    
    result = MyApp.UserActions.run(:create_user, params, %{current_user: user})
    
    assert_action_succeeds(result, fn created_user ->
      assert created_user.email == "test@example.com"
      assert created_user.name == "John"
    end)
  end
  
  test "require_admin step with helpers" do
    ctx = build_admin_context()
    
    assert_step_continues(MyApp.UserActions.require_admin(ctx))
  end
  
  test "require_admin fails for regular user" do
    ctx = build_user_context(build_user(role: "user"))
    
    assert_step_halts(MyApp.UserActions.require_admin(ctx), {:error, :unauthorized})
  end
end
```

## Testing Telemetry

### Capturing Telemetry Events

Create helpers to capture and assert on telemetry events:

```elixir
defmodule MyApp.TelemetryTestHelpers do
  def capture_telemetry(event_name, test_fn) do
    events = []
    ref = make_ref()
    
    :telemetry.attach(
      ref,
      event_name,
      fn event, measurements, metadata, acc ->
        send(self(), {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )
    
    try do
      test_fn.()
      
      receive_events(event_name, [])
    after
      :telemetry.detach(ref)
    end
  end
  
  def capture_all_axn_telemetry(test_fn) do
    events = []
    ref = make_ref()
    
    :telemetry.attach_many(
      ref,
      [
        [:axn, :action, :start],
        [:axn, :action, :stop],
        [:axn, :action, :exception]
      ],
      fn event, measurements, metadata, acc ->
        send(self(), {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )
    
    try do
      test_fn.()
      
      receive_events([:axn, :action], [])
    after
      :telemetry.detach(ref)
    end
  end
  
  defp receive_events(event_prefix, acc) do
    receive do
      {:telemetry_event, event, measurements, metadata} ->
        if event_matches?(event, event_prefix) do
          receive_events(event_prefix, [{event, measurements, metadata} | acc])
        else
          receive_events(event_prefix, acc)
        end
    after
      100 -> Enum.reverse(acc)
    end
  end
  
  defp event_matches?(event, prefix) when is_list(prefix) do
    List.starts_with?(event, prefix)
  end
  
  defp event_matches?(event, prefix) do
    event == prefix
  end
end
```

### Testing Telemetry Integration

```elixir
defmodule MyApp.UserActionsTelemetryTest do
  use ExUnit.Case
  import MyApp.TelemetryTestHelpers
  
  test "action emits start and stop events" do
    assigns = %{current_user: build_user(role: "admin")}
    params = %{"email" => "test@example.com", "name" => "John"}
    
    events = capture_all_axn_telemetry(fn ->
      MyApp.UserActions.run(:create_user, params, assigns)
    end)
    
    assert length(events) == 2
    
    [{start_event, start_measurements, start_metadata},
     {stop_event, stop_measurements, stop_metadata}] = events
    
    # Start event
    assert start_event == [:axn, :action, :start]
    assert start_metadata.module == MyApp.UserActions
    assert start_metadata.action == :create_user
    
    # Stop event  
    assert stop_event == [:axn, :action, :stop]
    assert stop_metadata.module == MyApp.UserActions
    assert stop_metadata.action == :create_user
    assert is_integer(stop_measurements.duration)
  end
  
  test "action emits exception event on failure" do
    assigns = %{current_user: build_user(role: "user")}  # Not admin
    params = %{"email" => "test@example.com", "name" => "John"}
    
    events = capture_all_axn_telemetry(fn ->
      MyApp.UserActions.run(:create_user, params, assigns)
    end)
    
    # Should have start and stop (not exception, since authorization failure is handled)
    assert length(events) == 2
    
    [{start_event, _, _}, {stop_event, _, _}] = events
    assert start_event == [:axn, :action, :start] 
    assert stop_event == [:axn, :action, :stop]
  end
  
  test "custom metadata is included in events" do
    assigns = %{
      current_user: build_user(role: "admin"),
      tenant: build_tenant(slug: "acme")
    }
    params = %{"email" => "test@example.com", "name" => "John"}
    
    events = capture_all_axn_telemetry(fn ->
      MyApp.UserActions.run(:create_user, params, assigns)
    end)
    
    [{_, _, start_metadata}, {_, _, stop_metadata}] = events
    
    # Custom metadata should be present
    assert start_metadata.tenant == "acme"
    assert stop_metadata.tenant == "acme"
    assert is_integer(start_metadata.user_id)
    assert is_integer(stop_metadata.user_id)
  end
end
```

## Property-Based Testing

For complex validation logic, consider property-based testing:

```elixir
defmodule MyApp.UserActions.PropertyTest do
  use ExUnit.Case
  use ExUnitProperties
  
  property "create_user always validates email format" do
    check all email <- string(:alphanumeric),
              name <- string(:alphanumeric, min_length: 1),
              not String.contains?(email, "@") do
      
      assigns = %{current_user: build_user(role: "admin")}
      params = %{"email" => email, "name" => name}
      
      result = MyApp.UserActions.run(:create_user, params, assigns)
      
      assert match?({:error, %{reason: :invalid_params}}, result)
    end
  end
  
  property "require_admin step behavior" do
    check all role <- member_of(["admin", "user", "moderator", nil]) do
      user = if role, do: build_user(role: role), else: nil
      ctx = build_context(assigns: %{current_user: user})
      
      result = MyApp.UserActions.require_admin(ctx)
      
      if role == "admin" do
        assert match?({:cont, _}, result)
      else
        assert match?({:halt, {:error, :unauthorized}}, result)
      end
    end
  end
end
```

## Integration Testing

### Full Pipeline Tests

Test complete scenarios that involve multiple actions:

```elixir
defmodule MyApp.UserWorkflowTest do
  use ExUnit.Case
  
  test "complete user onboarding workflow" do
    admin = build_user(role: "admin")
    
    # Step 1: Create user
    create_params = %{"email" => "new@example.com", "name" => "New User"}
    assert {:ok, user} = MyApp.UserActions.run(:create_user, create_params, %{current_user: admin})
    
    # Step 2: Send welcome email  
    assert {:ok, _} = MyApp.UserActions.run(:send_welcome_email, %{"user_id" => user.id}, %{current_user: admin})
    
    # Step 3: Setup user preferences
    prefs_params = %{"user_id" => user.id, "theme" => "dark", "notifications" => true}
    assert {:ok, _} = MyApp.UserActions.run(:setup_preferences, prefs_params, %{current_user: admin})
    
    # Verify final state
    updated_user = Users.get_user!(user.id)
    assert updated_user.email == "new@example.com"
    assert updated_user.preferences.theme == "dark"
    assert updated_user.preferences.notifications == true
  end
end
```

### Error Recovery Testing

```elixir
test "handles database errors gracefully" do
  # Setup database to fail
  Ecto.Adapters.SQL.Sandbox.checkout(MyApp.Repo)
  Ecto.Adapters.SQL.Sandbox.mode(MyApp.Repo, {:shared, self()})
  
  # Simulate connection loss
  :ok = Ecto.Adapters.SQL.Sandbox.stop_owner(MyApp.Repo, self())
  
  assigns = %{current_user: build_user(role: "admin")}
  params = %{"email" => "test@example.com", "name" => "John"}
  
  result = MyApp.UserActions.run(:create_user, params, assigns)
  
  # Should handle database error gracefully
  assert match?({:error, _reason}, result)
end
```

## Performance Testing

### Benchmark Actions

```elixir
defmodule MyApp.UserActionsBenchmark do
  use Benchee
  
  def run do
    assigns = %{current_user: build_user(role: "admin")}
    
    Benchee.run(%{
      "create_user" => fn ->
        params = %{"email" => "test#{:rand.uniform(10000)}@example.com", "name" => "John"}
        MyApp.UserActions.run(:create_user, params, assigns)
      end,
      
      "validate_only" => fn ->
        params = %{"email" => "test#{:rand.uniform(10000)}@example.com", "name" => "John"}
        ctx = build_context(assigns: assigns, params: params)
        MyApp.UserActions.validate_user_params(ctx)
      end
    })
  end
end
```

This comprehensive testing approach ensures your Axn actions are reliable, well-tested, and maintainable across different scenarios and edge cases.