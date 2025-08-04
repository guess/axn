# Telemetry Guide

Axn provides comprehensive telemetry integration using Elixir's standard `:telemetry` library. Every action automatically emits telemetry events with configurable metadata.

## Automatic Events

Axn automatically wraps every action execution with telemetry events using the standard `:telemetry.span/3` pattern:

```elixir
[:axn, :action, :start]     # When action starts
[:axn, :action, :stop]      # When action completes successfully
[:axn, :action, :exception] # When action fails with exception
```

These events are emitted automatically - no configuration required.

## Default Metadata

Every telemetry event includes standard metadata:

```elixir
%{
  module: MyApp.UserActions,  # The action module
  action: :create_user,       # The action name
  duration: 1234              # Only on :stop events (microseconds)
}
```

## Custom Metadata

You can add custom metadata at the module level and/or action level to provide more context for your telemetry consumers.

### Module-Level Metadata

Apply metadata to all actions in a module:

```elixir
defmodule MyApp.UserActions do
  use Axn, metadata: &__MODULE__.telemetry_metadata/1
  
  def telemetry_metadata(ctx) do
    %{
      user_id: ctx.assigns.current_user && ctx.assigns.current_user.id,
      tenant: ctx.assigns.tenant && ctx.assigns.tenant.slug,
      request_id: ctx.assigns.request_id
    }
  end
  
  action :create_user do
    step :validate_params
    step :create_user
  end
  
  action :update_user do
    step :validate_params  
    step :update_user
  end
end

# Both actions will include the custom metadata:
# %{module: MyApp.UserActions, action: :create_user, user_id: 123, tenant: "acme", request_id: "req_123"}
```

### Action-Level Metadata  

Add specific metadata for individual actions:

```elixir
defmodule MyApp.UserActions do
  use Axn, metadata: &__MODULE__.base_metadata/1
  
  action :create_user, metadata: &create_user_metadata/1 do
    step :validate_params
    step :create_user
  end
  
  def base_metadata(ctx) do
    %{
      user_id: ctx.assigns.current_user && ctx.assigns.current_user.id
    }
  end
  
  def create_user_metadata(ctx) do
    %{
      email_domain: extract_domain(ctx.params.email),
      admin_creation: admin?(ctx.assigns.current_user),
      signup_method: ctx.params[:method] || "standard"
    }
  end
  
  defp extract_domain(email) do
    email |> String.split("@") |> List.last()
  end
  
  defp admin?(user), do: user && user.role == "admin"
end

# Final metadata merges both functions:
# %{module: MyApp.UserActions, action: :create_user, user_id: 123, 
#   email_domain: "example.com", admin_creation: false, signup_method: "oauth"}
```

### Metadata Precedence

Metadata is merged in this order (later values override earlier ones):

1. **Default metadata**: `%{module: ModuleName, action: :action_name}`
2. **Module-level metadata**: From `use Axn, metadata: &function/1`  
3. **Action-level metadata**: From `action :name, metadata: &function/1`

## Subscribing to Events

Use standard `:telemetry` functions to subscribe to events:

```elixir
# Subscribe to successful completions
:telemetry.attach(
  "axn-action-success",
  [:axn, :action, :stop],
  &handle_action_success/4,
  nil
)

# Subscribe to failures
:telemetry.attach(
  "axn-action-failure", 
  [:axn, :action, :exception],
  &handle_action_failure/4,
  nil
)

# Subscribe to all events
:telemetry.attach_many(
  "axn-all-events",
  [
    [:axn, :action, :start],
    [:axn, :action, :stop], 
    [:axn, :action, :exception]
  ],
  &handle_axn_event/4,
  nil
)
```

## Event Handlers

### Basic Logging

```elixir
def handle_action_success(_event, measurements, metadata, _config) do
  Logger.info("Action completed", 
    module: metadata.module,
    action: metadata.action,
    duration_ms: div(measurements.duration, 1000),
    user_id: metadata[:user_id]
  )
end

def handle_action_failure(_event, measurements, metadata, _config) do
  Logger.error("Action failed",
    module: metadata.module,
    action: metadata.action,
    duration_ms: div(measurements.duration, 1000),
    user_id: metadata[:user_id],
    reason: metadata[:reason]
  )
end
```

### Metrics Collection

```elixir
def handle_axn_event([:axn, :action, :stop], measurements, metadata, _config) do
  # Prometheus metrics
  :prometheus_histogram.observe(
    :axn_action_duration_seconds,
    [module: metadata.module, action: metadata.action],
    measurements.duration / 1_000_000
  )
  
  # StatsD metrics  
  :statsd.timing("axn.action.duration", measurements.duration, 
    tags: ["module:#{metadata.module}", "action:#{metadata.action}"]
  )
end

def handle_axn_event([:axn, :action, :exception], _measurements, metadata, _config) do
  :prometheus_counter.inc(
    :axn_action_errors_total,
    [module: metadata.module, action: metadata.action]
  )
end
```

### Custom Analytics

```elixir
def handle_axn_event([:axn, :action, :stop], measurements, metadata, _config) do
  # Track user actions for analytics
  if metadata[:user_id] do
    Analytics.track_user_action(metadata.user_id, %{
      action: "#{metadata.module}.#{metadata.action}",
      duration_ms: div(measurements.duration, 1000),
      tenant: metadata[:tenant],
      result: :success
    })
  end
end
```

## Organizational Patterns

### Base Actions Module

Create a base module for consistent metadata across your application:

```elixir
defmodule MyApp.BaseActions do
  defmacro __using__(opts) do
    quote do
      use Axn, metadata: &MyApp.BaseActions.common_metadata/1
      
      # Additional module-specific metadata can still be added
      unquote(if opts[:metadata] do
        quote do
          def custom_metadata(ctx), do: unquote(opts[:metadata]).(ctx)
        end
      end)
    end
  end
  
  def common_metadata(ctx) do
    %{
      user_id: get_user_id(ctx),
      tenant_id: get_tenant_id(ctx),
      request_id: ctx.assigns[:request_id],
      environment: Application.get_env(:my_app, :environment)
    }
  end
  
  defp get_user_id(ctx) do
    case ctx.assigns.current_user do
      %{id: id} -> id
      _ -> nil
    end
  end
  
  defp get_tenant_id(ctx) do
    case ctx.assigns.tenant do
      %{id: id} -> id
      _ -> nil
    end
  end
end

# Usage in your action modules
defmodule MyApp.UserActions do
  use MyApp.BaseActions  # Gets common metadata automatically
  
  action :create_user do
    step :validate_params
    step :create_user
  end
end

defmodule MyApp.PaymentActions do  
  use MyApp.BaseActions  # Gets same common metadata
  
  action :process_payment, metadata: &payment_metadata/1 do
    step :validate_payment
    step :charge_card
  end
  
  def payment_metadata(ctx) do
    %{
      payment_method: ctx.params[:payment_method],
      amount_cents: ctx.params[:amount]
    }
  end
end
```

### Environment-Specific Configuration

```elixir
# config/config.exs
config :my_app, :telemetry,
  enabled: true,
  sample_rate: 1.0,
  include_sensitive_data: false

# config/prod.exs  
config :my_app, :telemetry,
  sample_rate: 0.1,  # Sample 10% of events in production
  include_sensitive_data: false

# In your metadata functions
def telemetry_metadata(ctx) do
  base_metadata = %{
    user_id: ctx.assigns.current_user && ctx.assigns.current_user.id,
    tenant: ctx.assigns.tenant && ctx.assigns.tenant.slug
  }
  
  if Application.get_env(:my_app, :telemetry)[:include_sensitive_data] do
    Map.merge(base_metadata, %{
      email: ctx.params[:email],
      ip_address: ctx.assigns[:remote_ip]
    })
  else
    base_metadata
  end
end
```

## Security Considerations

### Safe Metadata Extraction

Always be careful about what data you include in telemetry metadata:

```elixir
# ❌ DON'T - Sensitive data
def unsafe_metadata(ctx) do
  %{
    password: ctx.params[:password],          # Sensitive!
    credit_card: ctx.params[:credit_card],    # Sensitive!
    raw_params: ctx.params,                   # May contain sensitive data!
    changeset_errors: ctx.private[:changeset] # May expose internal details!
  }
end

# ✅ DO - Safe, aggregate data
def safe_metadata(ctx) do
  %{
    user_id: ctx.assigns.current_user && ctx.assigns.current_user.id,
    tenant: ctx.assigns.tenant && ctx.assigns.tenant.slug,
    param_count: map_size(ctx.params),
    has_file_upload: Map.has_key?(ctx.params, :file),
    request_type: get_request_type(ctx)
  }
end
```

### Sampling in Production

Consider sampling telemetry events in production to reduce overhead:

```elixir
def telemetry_metadata(ctx) do
  # Only include detailed metadata for sampled events
  base = %{user_id: get_user_id(ctx)}
  
  if should_include_detailed_metadata?() do
    Map.merge(base, %{
      tenant: ctx.assigns.tenant && ctx.assigns.tenant.slug,
      request_source: get_request_source(ctx),
      feature_flags: ctx.assigns[:feature_flags]
    })
  else
    base
  end
end

defp should_include_detailed_metadata? do
  :rand.uniform() < 0.1  # 10% sampling
end
```

## Performance Considerations

1. **Metadata functions are called for every action** - keep them fast and simple
2. **Avoid expensive operations** like database calls or external API requests
3. **Consider caching** computed values in the context if they're used multiple times
4. **Use sampling** in high-traffic production environments
5. **Telemetry has minimal overhead** when no handlers are attached

## Integration Examples

### Phoenix LiveDashboard

```elixir
# In your LiveDashboard metrics configuration
defp axn_metrics do
  [
    last_value("axn.action.duration",
      event_name: [:axn, :action, :stop],
      measurement: :duration,
      unit: {:microsecond, :second}
    ),
    
    counter("axn.action.count",
      event_name: [:axn, :action, :stop],
      tags: [:module, :action]
    ),
    
    counter("axn.action.errors",
      event_name: [:axn, :action, :exception], 
      tags: [:module, :action]
    )
  ]
end
```

### OpenTelemetry

```elixir
def handle_axn_event([:axn, :action, :start], _measurements, metadata, _config) do
  OpenTelemetry.Tracer.start_span("axn.action", %{
    "axn.module" => metadata.module,
    "axn.action" => metadata.action,
    "user.id" => metadata[:user_id]
  })
end

def handle_axn_event([:axn, :action, :stop], measurements, metadata, _config) do
  OpenTelemetry.Tracer.set_attribute("duration_ms", div(measurements.duration, 1000))
  OpenTelemetry.Tracer.end_span()
end
```

This telemetry system provides comprehensive observability into your Axn actions while maintaining security and performance best practices.