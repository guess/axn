# Advanced Guide

This guide covers advanced patterns and techniques for building sophisticated actions with Axn.

## Complex Validation Patterns

### Multi-Field Validation

Create custom validation functions that work across multiple fields:

```elixir
action :request_otp do
  step :cast_validate_params,
    schema: %{
      phone!: :string,
      region: [field: :string, default: "US"],
      challenge_token!: :string
    },
    validate: &validate_phone_and_token/1
    
  step :require_authenticated_user
  step :generate_and_send_otp

  defp validate_phone_and_token(changeset) do
    phone = Ecto.Changeset.get_field(changeset, :phone)
    region = Ecto.Changeset.get_field(changeset, :region)
    token = Ecto.Changeset.get_field(changeset, :challenge_token)

    changeset
    |> validate_phone_format(:phone, region: region)
    |> validate_challenge_token_not_expired(:challenge_token)
    |> validate_phone_token_pair(phone, token)
  end

  defp validate_phone_format(changeset, field, opts) do
    region = Keyword.get(opts, :region, "US")
    
    validate_change(changeset, field, fn field, phone ->
      case ExPhoneNumber.parse(phone, region) do
        {:ok, parsed} ->
          if ExPhoneNumber.is_valid_number?(parsed) do
            []
          else
            [{field, "is not a valid phone number for region #{region}"}]
          end
        {:error, _} ->
          [{field, "is not a valid phone number"}]
      end
    end)
  end

  defp validate_challenge_token_not_expired(changeset, field) do
    validate_change(changeset, field, fn field, token ->
      case Tokens.verify_challenge_token(token) do
        {:ok, _claims} -> []
        {:error, :expired} -> [{field, "has expired"}]
        {:error, _} -> [{field, "is invalid"}]
      end
    end)
  end

  defp validate_phone_token_pair(changeset, phone, token) do
    # Cross-field validation
    with {:ok, claims} <- Tokens.verify_challenge_token(token),
         true <- claims["phone"] == phone do
      changeset
    else
      _ -> add_error(changeset, :challenge_token, "does not match phone number")
    end
  end
end
```

### Conditional Validation

Apply different validation rules based on context:

```elixir
action :update_user do
  step :cast_validate_params,
    schema: %{
      id!: :integer,
      email: :string,
      name: :string,
      role: :string
    },
    validate: &validate_update_params/1
    
  step :authorize_update
  step :handle_update

  defp validate_update_params(changeset) do
    current_user = get_current_user_from_context()
    target_user_id = Ecto.Changeset.get_field(changeset, :id)
    
    changeset
    |> validate_email_if_changed()
    |> validate_role_change(current_user, target_user_id)
    |> validate_self_modification(current_user.id, target_user_id)
  end

  defp validate_role_change(changeset, current_user, target_user_id) do
    case Ecto.Changeset.get_change(changeset, :role) do
      nil -> changeset  # No role change
      new_role ->
        cond do
          current_user.role != "admin" ->
            add_error(changeset, :role, "can only be changed by administrators")
          current_user.id == target_user_id and new_role != "admin" ->
            add_error(changeset, :role, "administrators cannot demote themselves")
          new_role not in ["user", "admin", "moderator"] ->
            add_error(changeset, :role, "must be user, admin, or moderator")
          true ->
            changeset
        end
    end
  end
end
```

### Async Validation

For validation that requires external services:

```elixir
action :create_business_user do
  step :cast_validate_params,
    schema: %{
      email!: :string,
      company_domain!: :string,
      tax_id: :string
    },
    validate: &validate_business_details/1
    
  step :verify_business_async
  step :create_user

  defp validate_business_details(changeset) do
    changeset
    |> validate_business_email()
    |> validate_tax_id_format()
  end

  defp validate_business_email(changeset) do
    email = Ecto.Changeset.get_field(changeset, :email)
    domain = Ecto.Changeset.get_field(changeset, :company_domain)
    
    if email && domain do
      email_domain = email |> String.split("@") |> List.last()
      if email_domain == domain do
        changeset
      else
        add_error(changeset, :email, "must use company domain #{domain}")
      end
    else
      changeset
    end
  end

  def verify_business_async(ctx) do
    # Async verification step
    company_domain = ctx.params.company_domain
    tax_id = ctx.params[:tax_id]
    
    # Start async verification
    task = Task.async(fn ->
      BusinessVerification.verify_company(company_domain, tax_id)
    end)
    
    case Task.await(task, 10_000) do
      {:ok, business_info} ->
        {:cont, Context.assign(ctx, :business_verified, business_info)}
      {:error, reason} ->
        {:halt, {:error, %{reason: :business_verification_failed, details: reason}}}
    end
  rescue
    _ ->
      {:halt, {:error, :business_verification_timeout}}
  end
end
```

## External Steps and Libraries

### Creating Reusable Step Libraries

Organize common steps into reusable modules:

```elixir
defmodule MyApp.CommonSteps do
  @moduledoc """
  Reusable steps for common operations across actions.
  """
  
  alias Axn.Context
  
  def rate_limit(ctx, opts) do
    key = build_rate_limit_key(ctx, opts)
    limit = Keyword.get(opts, :limit, 100)
    window = Keyword.get(opts, :window, 60_000)  # 1 minute
    
    case RateLimiter.check_rate_limit(key, limit, window) do
      :ok -> 
        {:cont, ctx}
      {:error, :rate_limited} -> 
        {:halt, {:error, %{reason: :rate_limited, retry_after: window}}}
    end
  end
  
  def audit_log(ctx, opts) do
    action = Keyword.get(opts, :action, ctx.action)
    resource = Keyword.get(opts, :resource)
    
    audit_data = %{
      user_id: ctx.assigns[:current_user] && ctx.assigns.current_user.id,
      action: action,
      resource: resource,
      metadata: build_audit_metadata(ctx, opts)
    }
    
    case AuditLog.create(audit_data) do
      {:ok, _log} -> 
        {:cont, ctx}
      {:error, _reason} -> 
        # Don't fail the action for audit log failures
        Logger.warn("Failed to create audit log: #{inspect(audit_data)}")
        {:cont, ctx}
    end
  end
  
  def enrich_user_context(ctx, opts) do
    fields = Keyword.get(opts, :fields, [:preferences, :permissions])
    user = ctx.assigns[:current_user]
    
    if user do
      enriched_data = load_user_data(user, fields)
      {:cont, Context.assign(ctx, enriched_data)}
    else
      {:cont, ctx}
    end
  end
  
  def validate_feature_flag(ctx, opts) do
    flag = Keyword.fetch!(opts, :flag)
    user = ctx.assigns[:current_user]
    
    if FeatureFlags.enabled?(flag, user) do
      {:cont, ctx}
    else
      {:halt, {:error, %{reason: :feature_not_available, flag: flag}}}
    end
  end
  
  defp build_rate_limit_key(ctx, opts) do
    base_key = Keyword.get(opts, :key_prefix, "action")
    
    case Keyword.get(opts, :key_strategy, :user) do
      :user ->
        user_id = ctx.assigns[:current_user] && ctx.assigns.current_user.id
        "#{base_key}:user:#{user_id}"
      :ip ->
        ip = ctx.assigns[:remote_ip] || "unknown"
        "#{base_key}:ip:#{ip}"
      :global ->
        "#{base_key}:global"
      custom_fn when is_function(custom_fn, 1) ->
        custom_fn.(ctx)
    end
  end
  
  defp build_audit_metadata(ctx, opts) do
    %{
      params: sanitize_params_for_audit(ctx.params),
      source: get_source_type(ctx),
      tenant_id: ctx.assigns[:tenant] && ctx.assigns.tenant.id
    }
  end
  
  defp load_user_data(user, fields) do
    Enum.reduce(fields, %{}, fn field, acc ->
      case field do
        :preferences -> Map.put(acc, :user_preferences, UserPreferences.get(user))
        :permissions -> Map.put(acc, :user_permissions, Permissions.for_user(user))
        :billing -> Map.put(acc, :billing_info, Billing.get_account(user))
        _ -> acc
      end
    end)
  end
  
  defp sanitize_params_for_audit(params) do
    # Remove sensitive fields from audit logs
    Map.drop(params, ["password", "credit_card", "ssn", "token"])
  end
  
  defp get_source_type(ctx) do
    case Context.get_private(ctx, :source) do
      %Plug.Conn{} -> :api
      %Phoenix.LiveView.Socket{} -> :liveview
      _ -> :direct
    end
  end
end
```

### Using External Steps

```elixir
defmodule MyApp.UserActions do
  use Axn
  
  action :create_premium_user do
    step :cast_validate_params, schema: %{email!: :string, name!: :string}
    step {MyApp.CommonSteps, :rate_limit}, limit: 10, window: 60_000, key_strategy: :user
    step {MyApp.CommonSteps, :validate_feature_flag}, flag: :premium_accounts
    step :require_admin
    step {MyApp.CommonSteps, :enrich_user_context}, fields: [:billing, :permissions]
    step :create_premium_user
    step {MyApp.CommonSteps, :audit_log}, action: :create_premium_user, resource: :user
    
    def create_premium_user(ctx) do
      # Business logic here
      case Users.create_premium(ctx.params, ctx.assigns.billing_info) do
        {:ok, user} -> {:halt, {:ok, user}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end
  end
end
```

## Advanced Context Manipulation

### Context Builders

Create specialized context builders for complex scenarios:

```elixir
defmodule MyApp.ContextBuilders do
  alias Axn.Context
  
  def build_payment_context(ctx, payment_intent_id) do
    case Payments.get_intent(payment_intent_id) do
      {:ok, intent} ->
        ctx
        |> Context.assign(:payment_intent, intent)
        |> Context.assign(:payment_method, intent.payment_method) 
        |> Context.assign(:customer, intent.customer)
        |> Context.put_private(:payment_processor, :stripe)
      {:error, reason} ->
        Context.put_private(ctx, :payment_error, reason)
    end
  end
  
  def build_multi_tenant_context(ctx) do
    user = ctx.assigns[:current_user]
    
    case user && TenantResolver.resolve_tenant(user) do
      %Tenant{} = tenant ->
        ctx
        |> Context.assign(:tenant, tenant)
        |> Context.assign(:tenant_settings, tenant.settings)
        |> Context.put_private(:database_prefix, tenant.database_prefix)
      nil ->
        Context.put_private(ctx, :tenant_resolution_failed, true)
    end
  end
  
  def build_feature_context(ctx) do
    user = ctx.assigns[:current_user]
    tenant = ctx.assigns[:tenant]
    
    flags = FeatureFlags.for_user_and_tenant(user, tenant)
    
    ctx
    |> Context.assign(:feature_flags, flags)
    |> Context.put_private(:features_loaded, true)
  end
end

# Usage in actions
action :process_payment do
  step :validate_payment_params
  step :build_payment_context
  step :authorize_payment
  step :process_payment
  
  def build_payment_context(ctx) do
    intent_id = ctx.params.payment_intent_id
    enhanced_ctx = MyApp.ContextBuilders.build_payment_context(ctx, intent_id)
    
    if Context.get_private(enhanced_ctx, :payment_error) do
      {:halt, {:error, :invalid_payment_intent}}
    else
      {:cont, enhanced_ctx}
    end
  end
end
```

### Context Middleware Pattern

Create middleware-like steps for cross-cutting concerns:

```elixir
defmodule MyApp.ContextMiddleware do
  alias Axn.Context
  
  def tenant_scope(ctx, _opts) do
    tenant = ctx.assigns[:tenant]
    
    if tenant do
      # Set up tenant-scoped database queries
      Ecto.Query.put_query_prefix(MyApp.Repo, tenant.database_prefix)
      {:cont, Context.put_private(ctx, :tenant_scoped, true)}
    else
      {:halt, {:error, :tenant_required}}
    end
  end
  
  def transaction_wrapper(ctx, opts) do
    repo = Keyword.get(opts, :repo, MyApp.Repo)
    
    case repo.transaction(fn ->
      # Continue with remaining steps in transaction
      remaining_steps = Context.get_private(ctx, :remaining_steps, [])
      execute_steps_in_transaction(remaining_steps, ctx)
    end) do
      {:ok, result} -> result
      {:error, reason} -> {:halt, {:error, %{reason: :transaction_failed, details: reason}}}
    end
  end
  
  def cache_wrapper(ctx, opts) do
    cache_key = build_cache_key(ctx, opts)
    ttl = Keyword.get(opts, :ttl, 300)  # 5 minutes
    
    case Cache.get(cache_key) do
      {:ok, cached_result} ->
        {:halt, {:ok, cached_result}}
      :miss ->
        # Mark context to cache result after execution
        ctx = Context.put_private(ctx, :cache_key, cache_key)
        ctx = Context.put_private(ctx, :cache_ttl, ttl)
        {:cont, ctx}
    end
  end
  
  defp build_cache_key(ctx, opts) do
    base = Keyword.get(opts, :key_prefix, "action")
    action = ctx.action
    user_id = ctx.assigns[:current_user] && ctx.assigns.current_user.id
    params_hash = :crypto.hash(:md5, :erlang.term_to_binary(ctx.params))
    
    "#{base}:#{action}:#{user_id}:#{Base.encode16(params_hash)}"
  end
end
```

## Error Handling Patterns

### Structured Error Responses

Create consistent error structures across your application:

```elixir
defmodule MyApp.ErrorHandler do
  def handle_validation_error(changeset) do
    errors = Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    
    %{
      reason: :validation_failed,
      errors: errors,
      changeset: changeset
    }
  end
  
  def handle_business_error(error_code, details \\ nil) do
    error_map = %{
      reason: error_code,
      message: error_message(error_code),
      recoverable: recoverable_error?(error_code)
    }
    
    if details, do: Map.put(error_map, :details, details), else: error_map
  end
  
  defp error_message(:insufficient_funds), do: "Insufficient funds in account"
  defp error_message(:rate_limited), do: "Too many requests, please try again later"
  defp error_message(:feature_disabled), do: "This feature is currently disabled"
  defp error_message(:maintenance_mode), do: "System is in maintenance mode"
  defp error_message(code), do: "An error occurred: #{code}"
  
  defp recoverable_error?(:rate_limited), do: true
  defp recoverable_error?(:maintenance_mode), do: true
  defp recoverable_error?(:network_error), do: true
  defp recoverable_error?(_), do: false
end

# Usage in actions
def handle_payment(ctx) do
  case PaymentProcessor.charge(ctx.assigns.payment_intent) do
    {:ok, payment} ->
      {:halt, {:ok, payment}}
    {:error, :insufficient_funds} ->
      {:halt, {:error, MyApp.ErrorHandler.handle_business_error(:insufficient_funds)}}
    {:error, reason} ->
      {:halt, {:error, MyApp.ErrorHandler.handle_business_error(:payment_failed, reason)}}
  end
end
```

### Error Recovery Patterns

Implement retry and fallback mechanisms:

```elixir
defmodule MyApp.ResilienceSteps do
  def with_retry(ctx, opts) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    delay = Keyword.get(opts, :delay, 1000)
    step_fn = Keyword.fetch!(opts, :step)
    
    attempt_with_retry(ctx, step_fn, max_attempts, delay, 1)
  end
  
  defp attempt_with_retry(ctx, step_fn, max_attempts, delay, attempt) do
    case step_fn.(ctx) do
      {:cont, updated_ctx} ->
        {:cont, updated_ctx}
      {:halt, {:ok, result}} ->
        {:halt, {:ok, result}}
      {:halt, {:error, reason}} when attempt < max_attempts ->
        if recoverable_error?(reason) do
          :timer.sleep(delay * attempt)  # Exponential backoff
          attempt_with_retry(ctx, step_fn, max_attempts, delay, attempt + 1)
        else
          {:halt, {:error, reason}}
        end
      {:halt, {:error, reason}} ->
        {:halt, {:error, Map.merge(reason, %{attempts: attempt})}}
    end
  end
  
  def with_fallback(ctx, opts) do
    primary_step = Keyword.fetch!(opts, :primary)
    fallback_step = Keyword.fetch!(opts, :fallback)
    
    case primary_step.(ctx) do
      {:cont, updated_ctx} ->
        {:cont, updated_ctx}
      {:halt, {:ok, result}} ->
        {:halt, {:ok, result}}
      {:halt, {:error, reason}} ->
        Logger.warn("Primary step failed, attempting fallback: #{inspect(reason)}")
        
        case fallback_step.(ctx) do
          {:cont, fallback_ctx} ->
            {:cont, Context.put_private(fallback_ctx, :used_fallback, true)}
          {:halt, fallback_result} ->
            {:halt, fallback_result}
        end
    end
  end
  
  defp recoverable_error?(%{reason: :network_error}), do: true
  defp recoverable_error?(%{reason: :timeout}), do: true
  defp recoverable_error?(%{reason: :service_unavailable}), do: true
  defp recoverable_error?(_), do: false
end
```

## Performance Optimization

### Parallel Step Execution

For independent operations that can run in parallel:

```elixir
defmodule MyApp.ParallelSteps do
  def parallel_data_loading(ctx, _opts) do
    user = ctx.assigns.current_user
    
    tasks = [
      Task.async(fn -> {:preferences, UserPreferences.get(user)} end),
      Task.async(fn -> {:permissions, Permissions.for_user(user)} end),
      Task.async(fn -> {:billing, BillingAccount.get(user)} end),
      Task.async(fn -> {:notifications, Notifications.unread_count(user)} end)
    ]
    
    results = Task.await_many(tasks, 5000)
    
    enriched_data = Enum.into(results, %{})
    
    {:cont, Context.assign(ctx, enriched_data)}
  rescue
    e ->
      Logger.error("Parallel data loading failed: #{inspect(e)}")
      {:halt, {:error, :data_loading_failed}}
  end
end
```

### Conditional Step Execution

Skip expensive steps when possible:

```elixir
def conditional_enrichment(ctx, opts) do
  required_fields = Keyword.get(opts, :fields, [])
  user = ctx.assigns.current_user
  
  # Check what's already loaded
  missing_fields = required_fields -- loaded_fields(ctx)
  
  if Enum.empty?(missing_fields) do
    # All required data is already present
    {:cont, ctx}
  else
    # Only load missing data
    load_missing_data(ctx, user, missing_fields)
  end
end

defp loaded_fields(ctx) do
  ctx.assigns
  |> Map.keys()
  |> Enum.filter(&String.starts_with?(to_string(&1), "user_"))
  |> Enum.map(&String.replace(to_string(&1), "user_", ""))
  |> Enum.map(&String.to_existing_atom/1)
end
```

This advanced guide provides patterns for building sophisticated, production-ready actions that handle complex business requirements while maintaining clean, testable code.