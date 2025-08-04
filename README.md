# Axn - Unified Action DSL for Phoenix

A clean, step-based DSL library for defining actions that work seamlessly across Phoenix Controllers and LiveViews. Axn provides a unified interface for parameter validation, authorization, telemetry, and business logic where Plugs cannot be used.

**Why Axn?** Plugs only work with `Plug.Conn` but not `Phoenix.LiveView.Socket`. Axn bridges this gap, letting you write action logic once and use it in both contexts.

[![Hex.pm](https://img.shields.io/hexpm/v/axn.svg)](https://hex.pm/packages/axn)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/axn)

## Installation

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
    step :validate_params
    step :require_admin
    step :create_user

    def validate_params(ctx) do
      # Simple validation - details in docs
      {:cont, ctx}
    end

    def require_admin(ctx) do
      if admin?(ctx.assigns.current_user) do
        {:cont, ctx}
      else
        {:halt, {:error, :unauthorized}}
      end
    end

    def create_user(ctx) do
      case Users.create(ctx.params) do
        {:ok, user} -> {:halt, {:ok, user}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end

    defp admin?(user), do: user && user.role == "admin"
  end
end

# Use in Phoenix Controller
def create(conn, params) do
  case MyApp.UserActions.run(:create_user, params, conn) do
    {:ok, user} -> json(conn, %{user: user})
    {:error, reason} -> json(conn, %{error: reason})
  end
end

# Use in Phoenix LiveView
def handle_event("create_user", params, socket) do
  case MyApp.UserActions.run(:create_user, params, socket) do
    {:ok, user} -> {:noreply, assign(socket, :user, user)}
    {:error, reason} -> {:noreply, put_flash(socket, :error, "Error: #{reason}")}
  end
end
```

## Core Concepts

### Actions

Actions are named units of work that execute steps in order:

```elixir
action :action_name do
  step :step_name
  step :step_name, option: value
  step {ExternalModule, :external_step}
end
```

### Steps

Steps take a context and either continue or halt the pipeline:

```elixir
def my_step(ctx) do
  {:cont, updated_ctx}           # Continue to next step
  # OR
  {:halt, {:ok, result}}         # Stop with success
  # OR
  {:halt, {:error, reason}}      # Stop with error
end
```

### Context

The `Axn.Context` struct flows through steps, carrying data:

```elixir
%Axn.Context{
  action: :create_user,
  assigns: %{current_user: user},    # Phoenix-style assigns
  params: %{email: "...", name: "..."},  # Request parameters
  private: %{},                      # Internal state
  result: nil                        # Final result
}
```

## Built-in Steps

### Parameter Validation

```elixir
step :cast_validate_params, schema: %{
  email!: :string,                        # Required
  name: :string,                          # Optional
  age: [field: :integer, default: 18]     # With default
}

# With custom validation
step :cast_validate_params,
     schema: %{phone!: :string},
     validate: &validate_phone/1
```

## Authorization

Create simple authorization steps:

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


## Telemetry

Axn automatically emits telemetry events:

- `[:axn, :action, :start]` - Action starts
- `[:axn, :action, :stop]` - Action completes
- `[:axn, :action, :exception]` - Action fails

### Custom Metadata

```elixir
defmodule MyApp.UserActions do
  use Axn, metadata: &__MODULE__.telemetry_metadata/1

  def telemetry_metadata(ctx) do
    %{
      user_id: ctx.assigns.current_user && ctx.assigns.current_user.id,
      tenant: ctx.assigns.tenant && ctx.assigns.tenant.slug
    }
  end
end
```

See [Telemetry Guide](docs/telemetry.md) for advanced configuration.

## Unified Phoenix Integration

**The Problem:** Plugs work with Controllers but not LiveViews, creating code duplication.

**The Solution:** Axn works with both contexts seamlessly.

```elixir
# Same action works in both:
MyApp.UserActions.run(:create_user, params, conn)    # Controller
MyApp.UserActions.run(:create_user, params, socket)  # LiveView
```

The action automatically extracts assigns from either `conn` or `socket`, eliminating the need to duplicate authorization, validation, and business logic.

## Testing

```elixir
test "create_user succeeds with valid input" do
  assigns = %{current_user: %User{role: "admin"}}
  params = %{"email" => "test@example.com", "name" => "John"}

  assert {:ok, user} = MyApp.UserActions.run(:create_user, params, assigns)
  assert user.email == "test@example.com"
end
```

See [Testing Guide](docs/testing.md) for comprehensive test helpers.

## Error Handling

Axn provides consistent error handling:

```elixir
# Parameter errors
{:error, %{reason: :invalid_params, changeset: changeset}}

# Authorization errors
{:error, :unauthorized}

# Custom errors
{:error, :custom_reason}
```

## External Steps

Use steps from other modules:

```elixir
action :complex_operation do
  step :validate_params
  step {MySteps, :enrich_context}, fields: [:preferences]
  step :handle_operation
end
```

## Performance

- Minimal overhead when telemetry is disabled
- Efficient pipeline using `Enum.reduce_while/3`
- Steps are pure functions, easy to optimize

## Advanced Usage

For complex patterns, see:
- [Advanced Guide](docs/advanced.md) - Complex validation and external steps
- [Testing Guide](docs/testing.md) - Comprehensive test patterns

## Comparison

### vs. Phoenix Plugs
- **Plugs**: Work only with Controllers (`Plug.Conn`)
- **Axn**: Works with both Controllers and LiveViews

### vs. Phoenix Contexts
- **Contexts**: Business logic modules, manual integration
- **Axn**: Built-in Phoenix integration with parameter validation and telemetry

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

MIT
