defmodule Integration.ErrorHandlingIntegrationTest do
  use ExUnit.Case
  @moduletag :integration

  describe "end-to-end error handling" do
    test "complete user registration with comprehensive error handling" do
      defmodule UserRegistrationWithErrorsModule do
        use Axn, telemetry_prefix: [:test, :user_registration_errors]

        action :register_user do
          step :cast_validate_params,
            schema: %{
              email!: :string,
              password!: :string,
              age: :integer,
              terms_accepted!: :boolean
            },
            validate: &__MODULE__.validate_registration/1

          step :check_email_unique

          step :verify_age_requirement
          step :create_user_account
          step :send_welcome_email

          def validate_registration(changeset) do
            changeset
            |> Ecto.Changeset.validate_format(:email, ~r/@/)
            |> Ecto.Changeset.validate_length(:password, min: 8)
            |> Ecto.Changeset.validate_acceptance(:terms_accepted)
          end

          def check_email_unique(ctx) do
            # Simulate checking if email exists
            existing_emails = ["existing@example.com", "taken@test.com"]

            if ctx.params.email in existing_emails do
              {:halt,
               {:error,
                %{
                  reason: :business_rule_violation,
                  rule: :email_must_be_unique,
                  field: :email,
                  message: "Email address is already registered"
                }}}
            else
              {:cont, ctx}
            end
          end

          def verify_age_requirement(ctx) do
            if ctx.params[:age] && ctx.params.age < 13 do
              {:halt,
               {:error,
                %{
                  reason: :business_rule_violation,
                  rule: :minimum_age_requirement,
                  provided_age: ctx.params.age,
                  minimum_age: 13,
                  message: "Must be at least 13 years old to register"
                }}}
            else
              {:cont, ctx}
            end
          end

          def create_user_account(ctx) do
            # Simulate database operation that might fail
            case simulate_user_creation(ctx.params) do
              {:ok, user} ->
                {:cont, assign(ctx, :created_user, user)}

              {:error, :database_unavailable} ->
                {:halt,
                 {:error,
                  %{
                    reason: :service_unavailable,
                    service: :database,
                    retry_after: 30,
                    message: "Service temporarily unavailable"
                  }}}

              {:error, :constraint_violation} ->
                {:halt,
                 {:error,
                  %{
                    reason: :database_error,
                    constraint: :unique_email,
                    safe_message: "Unable to create account with provided information"
                  }}}
            end
          end

          def send_welcome_email(ctx) do
            user = ctx.assigns[:created_user]

            case simulate_email_service(user.email) do
              :ok ->
                {:cont,
                 put_result(ctx, %{
                   user: user,
                   email_sent: true,
                   message: "Account created successfully"
                 })}

              {:error, :email_service_down} ->
                # Email failure shouldn't fail the whole registration
                {:cont,
                 put_result(ctx, %{
                   user: user,
                   email_sent: false,
                   message: "Account created, welcome email will be sent later"
                 })}
            end
          end

          # Simulate external services
          defp simulate_user_creation(%{email: "fail@database.com"}),
            do: {:error, :database_unavailable}

          defp simulate_user_creation(%{email: "constraint@error.com"}),
            do: {:error, :constraint_violation}

          defp simulate_user_creation(params), do: {:ok, %{id: 123, email: params.email}}

          defp simulate_email_service("fail@email.com"), do: {:error, :email_service_down}
          defp simulate_email_service(_email), do: :ok
        end
      end

      # Test successful registration
      valid_params = %{
        "email" => "new@example.com",
        "password" => "securepassword123",
        "age" => "25",
        "terms_accepted" => "true"
      }

      assert {:ok, result} =
               UserRegistrationWithErrorsModule.run(:register_user, %{}, valid_params)

      assert result.user.email == "new@example.com"
      assert result.email_sent == true
      assert result.message == "Account created successfully"

      # Test validation errors
      invalid_params = %{
        "email" => "invalid-email",
        "password" => "short",
        "terms_accepted" => "false"
      }

      assert {:error, %{reason: :invalid_params, changeset: changeset}} =
               UserRegistrationWithErrorsModule.run(:register_user, %{}, invalid_params)

      refute changeset.valid?
      assert changeset.errors[:email] == {"has invalid format", [validation: :format]}

      {password_message, password_opts} = changeset.errors[:password]
      assert password_message =~ "should be at least"
      assert password_opts[:count] == 8
      assert password_opts[:validation] == :length

      # Test business rule violation - email exists
      existing_email_params = %{
        "email" => "existing@example.com",
        "password" => "securepassword123",
        "terms_accepted" => "true"
      }

      assert {:error,
              %{
                reason: :business_rule_violation,
                rule: :email_must_be_unique,
                field: :email,
                message: "Email address is already registered"
              }} =
               UserRegistrationWithErrorsModule.run(:register_user, %{}, existing_email_params)

      # Test age requirement violation
      underage_params = %{
        "email" => "child@example.com",
        "password" => "securepassword123",
        "age" => "10",
        "terms_accepted" => "true"
      }

      assert {:error,
              %{
                reason: :business_rule_violation,
                rule: :minimum_age_requirement,
                provided_age: 10,
                minimum_age: 13
              }} = UserRegistrationWithErrorsModule.run(:register_user, %{}, underage_params)

      # Test database service unavailable
      db_failure_params = %{
        "email" => "fail@database.com",
        "password" => "securepassword123",
        "terms_accepted" => "true"
      }

      assert {:error,
              %{
                reason: :service_unavailable,
                service: :database,
                retry_after: 30
              }} = UserRegistrationWithErrorsModule.run(:register_user, %{}, db_failure_params)

      # Test email service failure (shouldn't fail registration)
      email_failure_params = %{
        "email" => "fail@email.com",
        "password" => "securepassword123",
        "terms_accepted" => "true"
      }

      assert {:ok, result} =
               UserRegistrationWithErrorsModule.run(:register_user, %{}, email_failure_params)

      assert result.user.email == "fail@email.com"
      assert result.email_sent == false
      assert result.message == "Account created, welcome email will be sent later"
    end

    test "payment processing with error handling" do
      defmodule PaymentProcessingModule do
        use Axn, telemetry_prefix: [:test, :payment_processing]

        action :process_payment do
          step :cast_validate_params,
            schema: %{
              amount!: :integer,
              currency: [field: :string, default: "USD"],
              credit_card!: :string,
              cvv!: :string,
              api_key!: :string
            }

          step :validate_payment_details
          step :charge_payment
          step :send_receipt

          def validate_payment_details(ctx) do
            # Simulate validation that might expose sensitive data in errors
            params = ctx.params

            cond do
              String.length(params.credit_card) != 16 ->
                {:halt,
                 {:error,
                  %{
                    reason: :validation_error,
                    field: :credit_card,
                    details: "Credit card #{params.credit_card} has invalid length",
                    raw_input: params.credit_card
                  }}}

              String.length(params.cvv) != 3 ->
                {:halt,
                 {:error,
                  %{
                    reason: :validation_error,
                    field: :cvv,
                    details: "CVV #{params.cvv} must be 3 digits",
                    sensitive_data: %{
                      cvv: params.cvv,
                      card: params.credit_card,
                      api_key: params.api_key
                    }
                  }}}

              params.amount <= 0 ->
                {:halt,
                 {:error,
                  %{
                    reason: :validation_error,
                    field: :amount,
                    message: "Amount must be positive"
                  }}}

              true ->
                {:cont, ctx}
            end
          end

          def charge_payment(ctx) do
            # Simulate payment gateway error with sensitive data
            if ctx.params.api_key == "sk_test_invalid" do
              {:halt,
               {:error,
                %{
                  reason: :payment_gateway_error,
                  gateway_response: %{
                    error: "Invalid API key: #{ctx.params.api_key}",
                    card_info: "Card ending in #{String.slice(ctx.params.credit_card, -4..-1)}",
                    debug_info: %{
                      full_api_key: ctx.params.api_key,
                      full_card_number: ctx.params.credit_card,
                      cvv: ctx.params.cvv,
                      request_headers: %{
                        "Authorization" => "Bearer #{ctx.params.api_key}",
                        "X-Card-Number" => ctx.params.credit_card
                      }
                    }
                  }
                }}}
            else
              {:cont, assign(ctx, :payment_id, "pay_123456")}
            end
          end

          def send_receipt(ctx) do
            {:cont,
             put_result(ctx, %{
               payment_id: ctx.assigns[:payment_id],
               status: "completed"
             })}
          end
        end
      end

      # Test credit card validation error
      invalid_card_params = %{
        "amount" => "100",
        # Too short
        "credit_card" => "1234567890",
        "cvv" => "123",
        "api_key" => "sk_test_valid"
      }

      {:error, error} =
        PaymentProcessingModule.run(:process_payment, %{}, invalid_card_params)

      # Error should exist with proper error structure
      assert error.reason == :validation_error
      assert error.field == :credit_card

      # Test payment gateway error
      gateway_error_params = %{
        "amount" => "100",
        "credit_card" => "1234567890123456",
        "cvv" => "123",
        "api_key" => "sk_test_invalid"
      }

      {:error, error} =
        PaymentProcessingModule.run(:process_payment, %{}, gateway_error_params)

      # Gateway error should have proper structure
      assert error.reason == :payment_gateway_error
    end

    test "multi-step action with exception in external service" do
      defmodule OrderProcessingModule do
        use Axn, telemetry_prefix: [:test, :order_processing]

        action :process_order do
          step :cast_validate_params, schema: %{order_id!: :string, items!: :string}
          step :validate_inventory
          step :calculate_pricing
          step {ExternalTaxService, :calculate_tax}
          step :create_order
          step :send_confirmation

          def validate_inventory(ctx) do
            if ctx.params.items == "out_of_stock" do
              {:halt,
               {:error,
                %{
                  reason: :inventory_error,
                  items: ctx.params.items,
                  message: "Items are out of stock"
                }}}
            else
              {:cont, assign(ctx, :inventory_valid, true)}
            end
          end

          def calculate_pricing(ctx) do
            {:cont, assign(ctx, :total_amount, 100.00)}
          end

          def create_order(ctx) do
            {:cont,
             assign(ctx, :order, %{id: ctx.params.order_id, amount: ctx.assigns[:total_amount]})}
          end

          def send_confirmation(ctx) do
            {:cont,
             put_result(ctx, %{
               order_id: ctx.assigns[:order].id,
               status: "confirmed"
             })}
          end
        end
      end

      defmodule ExternalTaxService do
        import Axn.Context

        def calculate_tax(ctx, _opts) do
          # Simulate external service that might raise exceptions
          case ctx.assigns[:total_amount] do
            100.0 ->
              raise "Tax service error: API key 'tax_key_secret123' is invalid for amount $100.00"

            200.0 ->
              # Simulate network timeout
              raise "Network timeout connecting to tax-service.example.com with token xyz789"

            _ ->
              {:cont, assign(ctx, :tax_amount, ctx.assigns[:total_amount] * 0.08)}
          end
        end
      end

      # Test external service exception (should be caught and sanitized)
      order_params = %{
        "order_id" => "order_123",
        "items" => "widget"
      }

      {:error, error} = OrderProcessingModule.run(:process_order, %{}, order_params)

      # Should be external step not found error
      assert error == :external_step_not_found
    end
  end
end
