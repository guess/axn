# Axn - Unified Action DSL for Phoenix

A clean, step-based DSL library for defining actions that work seamlessly across Phoenix Controllers and LiveViews. Axn provides a unified interface for parameter validation, authorization, telemetry, and business logic where Plugs cannot be used.

**Why Axn?** Plugs only work with `Plug.Conn` but not `Phoenix.LiveView.Socket`. Axn bridges this gap, letting you write action logic once and use it in both contexts.

[![Hex.pm](https://img.shields.io/hexpm/v/axn.svg)](https://hex.pm/packages/axn)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/axn)

## Features

- **Unified Phoenix Integration**: Same action logic works in Controllers and LiveViews
- **Beyond Plugs**: Works where Plugs cannot - with LiveView Sockets
- **Explicit over implicit**: Each action clearly shows its execution flow
- **Composable**: Steps are reusable across actions and modules
- **Safe by default**: Telemetry and error handling don't leak sensitive data
- **Simple to implement**: Minimal macro magic, straightforward execution model
- **Easy to test**: Steps are pure functions that are easy to unit test

## Installation

Add `axn` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:axn, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
defmodule MyApp.UserActions do
  use Axn

  action :create_user do
    step :cast_validate_params, schema: %{email!: :string, name!: :string}
    step :require_admin
    step :handle_create

    def require_admin(ctx) do
      if admin?(ctx.assigns.current_user) do
        {:cont, ctx}
      else
        {:halt, {:error, :unauthorized}}
      end
    end

    def handle_create(ctx) do
      case Users.create(ctx.params) do
        {:ok, user} -> {:halt, {:ok, user}}
        {:error, changeset} -> {:halt, {:error, %{reason: :creation_failed, changeset: changeset}}}
      end
    end

    defp admin?(user), do: user && user.role == "admin"
  end
end

# In your Phoenix controller
defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller

  def create(conn, params) do
    case MyApp.UserActions.run(:create_user, params, conn) do
      {:ok, user} ->
        json(conn, %{success: true, user: user})
      {:error, %{reason: :invalid_params, changeset: changeset}} ->
        json(conn, %{errors: format_changeset_errors(changeset)})
      {:error, reason} ->
        json(conn, %{error: reason})
    end
  end
end
```

## Core Concepts

### Actions

Actions are named units of work that execute a series of steps in order. Each action automatically gets telemetry wrapping and error handling.

```elixir
action :action_name do
  step :step_name
  step :step_name, option: value
  step {ExternalModule, :external_step}, option: value
end
```

### Steps

Steps are individual functions that take a context and either continue the pipeline or halt it. Steps follow a simple contract:

```elixir
step_function(ctx) -> {:cont, new_ctx} | {:halt, result}
step_function(ctx, opts) -> {:cont, new_ctx} | {:halt, result}
```

**Return Values:**
- `{:cont, new_ctx}` - Continue to next step with updated context
- `{:halt, {:ok, result}}` - Stop pipeline with success result
- `{:halt, {:error, reason}}` - Stop pipeline with error

### Context

An `Axn.Context` struct flows through the step pipeline, carrying request data, user information, and step-added fields.

```elixir
# Before parameter validation
%Axn.Context{
  action: :create_user,              # Current action name
  assigns: %{current_user: user},    # Phoenix-style assigns
  params: %{"email" => "...", "name" => "..."},  # Raw parameters initially
  private: %{},                      # Internal DSL state
  result: nil                        # Action result
}

# After cast_validate_params step
%Axn.Context{
  action: :create_user,              # Current action name
  assigns: %{current_user: user},    # Phoenix-style assigns
  params: %{email: "...", name: "..."},  # Cast and validated parameters
  private: %{raw_params: %{"email" => "...", "name" => "..."}, changeset: #Changeset<>},
  result: nil                        # Action result
}
```

#### Context Helper Functions

```elixir
# Assign values (like Phoenix.Component.assign/3)
Context.assign(ctx, :current_user, user)
Context.assign(ctx, %{current_user: user, theme: "dark"})
Context.assign(ctx, current_user: user, theme: "dark")

# Get private values
Context.get_private(ctx, :correlation_id)           # Returns value or nil
Context.get_private(ctx, :correlation_id, "default") # Returns value or default

# Put private values (like Plug.Conn.put_private/3)
Context.put_private(ctx, :correlation_id, id)
Context.put_private(ctx, :changeset, changeset)

# Update params and result
Context.put_params(ctx, validated_params)
Context.put_result(ctx, {:ok, user})
```

## Built-in Steps

### Parameter Validation

The `:cast_validate_params` step provides parameter casting and validation:

```elixir
step :cast_validate_params, schema: %{
  field_name!: :type,                    # Required field
  field_name: :type,                     # Optional field
  field_name: [field: :type, default: value], # With default
  field_name: [field: :type, cast: &func/1]   # With custom cast function
}

# With custom validation function
step :cast_validate_params,
  schema: %{phone!: :string, region: [field: :string, default: "US"]},
  validate: &validate_phone_number/1

defp validate_phone_number(changeset) do
  # Apply additional validation logic
  changeset
  |> cast_validate_phone_number(:phone, region: get_field(changeset, :region))
end
```

## Authorization Patterns

Axn doesn't provide a built-in authorization step since authorization is application-specific. Instead, use these patterns:

### Simple Role Check

```elixir
step :require_admin

def require_admin(ctx) do
  if admin?(ctx.assigns.current_user) do
    {:cont, ctx}
  else
    {:halt, {:error, :unauthorized}}
  end
end
```

### Resource-Based Authorization

```elixir
step :authorize_user_access

def authorize_user_access(ctx) do
  if can_access?(ctx.assigns.current_user, ctx.params.user_id) do
    {:cont, ctx}
  else
    {:halt, {:error, :unauthorized}}
  end
end
```

### Action-Based Authorization

```elixir
step :authorize_action

def authorize_action(ctx) do
  if allowed?(ctx.assigns.current_user, ctx.action) do
    {:cont, ctx}
  else
    {:halt, {:error, :unauthorized}}
  end
end
```

## Telemetry Integration

Axn automatically emits telemetry events for every action using the standard `:telemetry.span/3` pattern:

### Fixed Event Names

All Axn actions emit events with fixed names for consistency:

```elixir
[:axn, :action, :start]     # When action starts
[:axn, :action, :stop]      # When action completes
[:axn, :action, :exception] # When action fails with exception
```

### Basic Usage

```elixir
defmodule MyApp.UserActions do
  use Axn
  
  action :create_user do
    step :validate_params
    step :create_user
  end
end

# Default metadata: %{module: MyApp.UserActions, action: :create_user}
```

### Custom Metadata

You can add custom metadata at the module level and/or action level:

#### Module-Level Metadata

```elixir
defmodule MyApp.UserActions do
  use Axn, metadata: &__MODULE__.telemetry_metadata/1
  
  def telemetry_metadata(ctx) do
    %{
      user_id: ctx.assigns.current_user && ctx.assigns.current_user.id,
      tenant: ctx.assigns.tenant && ctx.assigns.tenant.slug
    }
  end
  
  action :create_user do
    step :validate_params
    step :create_user
  end
end

# Metadata: %{module: MyApp.UserActions, action: :create_user, user_id: "123", tenant: "acme"}
```

#### Action-Level Metadata

```elixir
defmodule MyApp.UserActions do
  use Axn, metadata: &__MODULE__.module_metadata/1
  
  action :create_user, metadata: &create_user_metadata/1 do
    step :validate_params
    step :create_user
  end
  
  def module_metadata(ctx) do
    %{user_id: ctx.assigns.current_user && ctx.assigns.current_user.id}
  end
  
  def create_user_metadata(ctx) do
    %{
      email_domain: extract_domain(ctx.params.email),
      admin_creation: admin?(ctx.assigns.current_user)
    }
  end
end

# Final metadata includes both module and action metadata:
# %{module: MyApp.UserActions, action: :create_user, user_id: "123", 
#   email_domain: "example.com", admin_creation: false}
```

#### Metadata Precedence

Metadata is merged in this order (later overrides earlier):
1. **Default**: `%{module: ModuleName, action: :action_name}`
2. **Module-level**: From `use Axn, metadata: &function/1`
3. **Action-level**: From `action :name, metadata: &function/1`

### Subscribing to Events

```elixir
:telemetry.attach(
  "my-handler",
  [:axn, :action, :stop],
  &handle_action_complete/4,
  nil
)

def handle_action_complete(event, measurements, metadata, _config) do
  Logger.info("#{metadata.module}.#{metadata.action} completed in #{measurements.duration}μs")
end
```

### Organizational Patterns

Create base modules for consistent metadata across your application:

```elixir
defmodule MyApp.BaseActions do
  defmacro __using__(_opts) do
    quote do
      use Axn, metadata: &MyApp.BaseActions.common_metadata/1
    end
  end
  
  def common_metadata(ctx) do
    %{
      user_id: ctx.assigns.current_user && ctx.assigns.current_user.id,
      tenant_id: ctx.assigns.tenant && ctx.assigns.tenant.id,
      request_id: ctx.assigns.request_id
    }
  end
end

# Now all your action modules get common metadata automatically
defmodule MyApp.UserActions do
  use MyApp.BaseActions  # Gets common metadata
  
  action :create_user, metadata: &create_metadata/1 do
    # Action-specific metadata still available
  end
end
```

## External Steps

You can use steps defined in other modules:

```elixir
defmodule MySteps do
  def enrich_context(ctx, opts) do
    fields = Keyword.get(opts, :fields, [])
    # Enrich context with external data
    {:cont, Context.assign(ctx, :enriched, true)}
  end
end

defmodule MyActions do
  use Axn

  action :complex_operation do
    step :cast_validate_params, schema: %{data!: :string}
    step {MySteps, :enrich_context}, fields: [:preferences, :billing]
    step :handle_operation
  end
end
```

## Testing

Axn provides comprehensive test helpers to make testing actions and steps easy:

```elixir
defmodule MyApp.UserActionsTest do
  use ExUnit.Case
  import Axn.TestHelpers

  test "create_user succeeds with valid input" do
    assigns = %{current_user: build_user(role: "admin")}
    params = %{"email" => "test@example.com", "name" => "John Doe"}

    assert_action_succeeds(
      MyApp.UserActions.run(:create_user, params, assigns),
      fn user ->
        assert user.email == "test@example.com"
        assert user.name == "John Doe"
      end
    )
  end

  test "create_user fails authorization" do
    assigns = %{current_user: build_user(role: "user")}
    params = %{"email" => "test@example.com", "name" => "John Doe"}

    assert_action_fails(
      MyApp.UserActions.run(:create_user, params, assigns),
      :unauthorized
    )
  end
end
```

### Testing Individual Steps

```elixir
test "validate_email step works correctly" do
  ctx = build_context(
    params: %{email: "test@example.com"},
    assigns: %{current_user: build_user()}
  )

  assert_step_continues(MySteps.validate_email(ctx), fn updated_ctx ->
    assert updated_ctx.assigns.email_valid == true
  end)
end
```

### Test Helpers

- `build_context/1` - Create test contexts with common defaults
- `build_user/1` - Create test users with various roles
- `capture_telemetry/1` - Capture telemetry events during tests
- `assert_action_succeeds/2` - Assert action success with result validation
- `assert_action_fails/2` - Assert action failure with reason validation
- `assert_step_continues/2` - Assert step continues with context validation
- `assert_step_halts/2` - Assert step halts with result validation

## Error Handling

Axn provides comprehensive error handling:

```elixir
# Parameter validation errors
{:error, %{reason: :invalid_params, changeset: changeset}}

# Authorization errors
{:error, :unauthorized}

# Custom business logic errors
{:error, :custom_business_error}
{:error, %{reason: :complex_error, details: "..."}}

# Step exceptions are caught and converted
{:error, %{reason: :step_error}}
```

## Performance

Axn is designed for high performance:

- Minimal overhead when telemetry is disabled
- Efficient step pipeline using `Enum.reduce_while/3`
- Context mutations don't accumulate large data structures
- Steps can be tested independently for performance

## Unified Phoenix Integration

**The Problem:** Plugs work great for Phoenix Controllers (with `Plug.Conn`) but cannot be used with Phoenix LiveViews (with `Phoenix.LiveView.Socket`). This creates code duplication when you need the same authorization, rate limiting, data loading, or business logic in both contexts.

**The Solution:** Axn provides a unified action interface that works seamlessly with both Controllers and LiveViews, eliminating the need to duplicate logic across these different Phoenix contexts.

### Unified API

Axn actions use a consistent interface that works across Phoenix contexts:

```elixir
MyApp.UserActions.run(action, params, source)
```

The `source` parameter provides context and can be:
- **Phoenix Controller**: Pass the full `conn` 
- **Phoenix LiveView**: Pass the full `socket`
- **Direct calls/tests**: Pass a plain assigns map

Axn automatically extracts assigns from the source while preserving access to the original context.

### Example: Unified User Creation

Define the action once:

```elixir
defmodule MyApp.UserActions do
  use Axn

  action :create_user do
    step :cast_validate_params, schema: %{email!: :string, name!: :string}
    step :require_admin
    step :create_user_record
    step :send_welcome_email

    def require_admin(ctx) do
      if admin?(ctx.assigns.current_user) do
        {:cont, ctx}
      else
        {:halt, {:error, :unauthorized}}
      end
    end

    def create_user_record(ctx) do
      case Users.create(ctx.params) do
        {:ok, user} -> {:cont, assign(ctx, :user, user)}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end

    def send_welcome_email(ctx) do
      # Access original source for context-specific behavior
      source = get_private(ctx, :source)
      
      case source do
        %Plug.Conn{} -> 
          # API - send email async
          WelcomeEmail.send_async(ctx.assigns.user)
        %Phoenix.LiveView.Socket{} ->
          # LiveView - send email and show flash
          WelcomeEmail.send_async(ctx.assigns.user)
      end
      
      {:halt, {:ok, ctx.assigns.user}}
    end
  end
end
```

Use in Phoenix Controller:

```elixir
def create(conn, params) do
  case MyApp.UserActions.run(:create_user, params, conn) do
    {:ok, user} -> json(conn, %{user: user})
    {:error, reason} -> json(conn, %{error: reason})
  end
end
```

Use in Phoenix LiveView:

```elixir
def handle_event("create_user", params, socket) do
  case MyApp.UserActions.run(:create_user, params, socket) do
    {:ok, user} -> 
      {:noreply, socket |> put_flash(:info, "User created!") |> assign(:user, user)}
    {:error, reason} -> 
      {:noreply, put_flash(socket, :error, "Failed: #{reason}")}
  end
end
```

**Key Benefits:**
- Same authorization logic (`require_admin`) works in both contexts
- Same validation logic works in both contexts  
- Same business logic works in both contexts
- Context-specific behavior when needed (email handling)
- No code duplication between Controller and LiveView

## Advanced Usage

### Custom Validation with Multiple Fields

```elixir
action :request_otp do
  step :cast_validate_params,
    schema: %{
      phone!: :string,
      region: [field: :string, default: "US"],
      challenge_token!: :string
    },
    validate: &validate_phone_and_token/1

  defp validate_phone_and_token(changeset) do
    phone = Ecto.Changeset.get_field(changeset, :phone)
    region = Ecto.Changeset.get_field(changeset, :region)

    changeset
    |> validate_phone_format(:phone, region)
    |> validate_challenge_token_not_expired(:challenge_token)
  end
end
```

### Multiple Actions per Module

```elixir
defmodule MyApp.UserActions do
  use Axn

  action :create_user do
    step :cast_validate_params, schema: %{email!: :string, name!: :string}
    step :require_admin
    step :handle_create_user
  end

  action :update_user do
    step :cast_validate_params, schema: %{id!: :integer, name: :string}
    step :authorize_user_update
    step :handle_update_user
  end

  action :delete_user do
    step :cast_validate_params, schema: %{id!: :integer}
    step :require_admin
    step :handle_delete_user
  end

  # Shared step implementations...
end
```

### Complex Context Manipulation

```elixir
def enrich_user_context(ctx) do
  user = ctx.assigns.current_user

  ctx
  |> Context.assign(:user_preferences, load_preferences(user))
  |> Context.assign(:user_permissions, load_permissions(user))
  |> Context.put_private(:audit_trail, start_audit(user))
  |> then(fn enriched_ctx -> {:cont, enriched_ctx} end)
end
```

## Comparison with Other Libraries

### vs. Phoenix Plugs

- **Plugs**: Work only with `Plug.Conn` (Controllers), great for HTTP-specific logic
- **Axn**: Works with both `Plug.Conn` and `Phoenix.LiveView.Socket`, unified business logic

### vs. Phoenix Contexts

- **Contexts**: Business logic modules, but require manual integration in Controllers/LiveViews  
- **Axn**: Built-in integration patterns with automatic parameter validation, authorization, and telemetry

### vs. Commanded/EventStore

- **Axn**: Simple request/response actions with unified Phoenix integration
- **Commanded**: Full CQRS/Event Sourcing with complex state management

### vs. Sage

- **Axn**: Step-based actions optimized for Phoenix Controller/LiveView unification  
- **Sage**: Transaction-like operations with compensation

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Add tests for your changes
4. Ensure all tests pass (`mix test`)
5. Run static analysis (`mix credo`)
6. Commit your changes (`git commit -am 'Add some feature'`)
7. Push to the branch (`git push origin my-new-feature`)
8. Create a new Pull Request

## License

Copyright © 2024 Steve Gentry

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
