defmodule Integration.AuthorizationPatternsIntegrationTest do
  use ExUnit.Case
  @moduletag :integration

  describe "authorization patterns" do
    test "simple role-based authorization" do
      defmodule AdminActions do
        use Axn, telemetry_prefix: [:test, :admin]

        action :admin_only_action do
          step :require_admin
          step :perform_admin_task

          def require_admin(ctx) do
            if admin?(ctx.assigns[:current_user]) do
              {:cont, ctx}
            else
              {:halt, {:error, :unauthorized}}
            end
          end

          def perform_admin_task(ctx) do
            {:cont, put_result(ctx, "Admin task completed")}
          end

          defp admin?(user), do: user && user.role == "admin"
        end
      end

      # Test successful admin access
      admin_user = %{id: 1, role: "admin"}
      assigns = %{current_user: admin_user}

      assert {:ok, "Admin task completed"} = AdminActions.run(:admin_only_action, assigns, %{})

      # Test unauthorized access
      regular_user = %{id: 2, role: "user"}
      assigns = %{current_user: regular_user}

      assert {:error, :unauthorized} = AdminActions.run(:admin_only_action, assigns, %{})

      # Test no user
      assert {:error, :unauthorized} = AdminActions.run(:admin_only_action, %{}, %{})
    end

    test "resource-based authorization" do
      defmodule UserActions do
        use Axn, telemetry_prefix: [:test, :user_auth]

        action :update_user do
          step :cast_validate_params, schema: %{user_id!: :integer, name: :string}
          step :authorize_user_access
          step :update_user_record

          def authorize_user_access(ctx) do
            current_user = ctx.assigns[:current_user]
            target_user_id = ctx.params.user_id

            if can_access?(current_user, target_user_id) do
              {:cont, ctx}
            else
              {:halt, {:error, :unauthorized}}
            end
          end

          def update_user_record(ctx) do
            {:cont, put_result(ctx, "User updated successfully")}
          end

          defp can_access?(user, target_user_id) do
            user && (user.id == target_user_id || user.role == "admin")
          end
        end
      end

      # Test user updating their own record
      user = %{id: 123, role: "user"}
      assigns = %{current_user: user}
      params = %{"user_id" => "123", "name" => "New Name"}

      assert {:ok, "User updated successfully"} = UserActions.run(:update_user, assigns, params)

      # Test admin updating another user's record
      admin = %{id: 456, role: "admin"}
      assigns = %{current_user: admin}

      assert {:ok, "User updated successfully"} = UserActions.run(:update_user, assigns, params)

      # Test unauthorized access (different user, not admin)
      other_user = %{id: 789, role: "user"}
      assigns = %{current_user: other_user}

      assert {:error, :unauthorized} = UserActions.run(:update_user, assigns, params)
    end

    test "action-based authorization pattern" do
      defmodule ActionAuthModule do
        use Axn, telemetry_prefix: [:test, :action_auth]

        action :sensitive_action do
          step :authorize_action
          step :perform_action

          def authorize_action(ctx) do
            user = ctx.assigns[:current_user]
            action = ctx.action

            if allowed?(user, action) do
              {:cont, ctx}
            else
              {:halt, {:error, :unauthorized}}
            end
          end

          def perform_action(ctx) do
            {:cont, put_result(ctx, "Sensitive action completed")}
          end

          defp allowed?(user, :sensitive_action) do
            user && user.permissions && :sensitive_action in user.permissions
          end

          defp allowed?(_, _), do: false
        end
      end

      # Test user with permission
      authorized_user = %{id: 1, permissions: [:sensitive_action, :other_action]}
      assigns = %{current_user: authorized_user}

      assert {:ok, "Sensitive action completed"} =
               ActionAuthModule.run(:sensitive_action, assigns, %{})

      # Test user without permission
      unauthorized_user = %{id: 2, permissions: [:other_action]}
      assigns = %{current_user: unauthorized_user}

      assert {:error, :unauthorized} = ActionAuthModule.run(:sensitive_action, assigns, %{})
    end
  end
end
