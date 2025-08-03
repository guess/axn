defmodule Axn.ContextTest do
  use ExUnit.Case

  describe "Axn.Context struct" do
    test "has correct default fields" do
      ctx = %Axn.Context{}

      assert ctx.action == nil
      assert ctx.assigns == %{}
      assert ctx.params == %{}
      assert ctx.private == %{}
      assert ctx.result == nil
    end

    test "can be created with custom fields" do
      ctx = %Axn.Context{
        action: :test_action,
        assigns: %{current_user: %{id: 123}},
        params: %{name: "John"},
        private: %{raw_params: %{"name" => "John"}},
        result: {:ok, "success"}
      }

      assert ctx.action == :test_action
      assert ctx.assigns == %{current_user: %{id: 123}}
      assert ctx.params == %{name: "John"}
      assert ctx.private == %{raw_params: %{"name" => "John"}}
      assert ctx.result == {:ok, "success"}
    end
  end

  describe "Axn.Context.assign/3" do
    test "assigns a single key-value pair" do
      ctx = %Axn.Context{}
      updated_ctx = Axn.Context.assign(ctx, :current_user, %{id: 123})

      assert updated_ctx.assigns == %{current_user: %{id: 123}}
      # Should return new context
      assert updated_ctx != ctx
    end

    test "updates existing assignment" do
      ctx = %Axn.Context{assigns: %{current_user: %{id: 123}}}
      updated_ctx = Axn.Context.assign(ctx, :current_user, %{id: 456})

      assert updated_ctx.assigns == %{current_user: %{id: 456}}
    end

    test "preserves other assignments" do
      ctx = %Axn.Context{assigns: %{current_user: %{id: 123}, theme: "dark"}}
      updated_ctx = Axn.Context.assign(ctx, :locale, "en")

      assert updated_ctx.assigns == %{current_user: %{id: 123}, theme: "dark", locale: "en"}
    end
  end

  describe "Axn.Context.assign/2 with map" do
    test "assigns multiple key-value pairs from map" do
      ctx = %Axn.Context{}
      updated_ctx = Axn.Context.assign(ctx, %{current_user: %{id: 123}, theme: "dark"})

      assert updated_ctx.assigns == %{current_user: %{id: 123}, theme: "dark"}
    end

    test "merges with existing assignments" do
      ctx = %Axn.Context{assigns: %{locale: "en"}}
      updated_ctx = Axn.Context.assign(ctx, %{current_user: %{id: 123}, theme: "dark"})

      assert updated_ctx.assigns == %{locale: "en", current_user: %{id: 123}, theme: "dark"}
    end

    test "overwrites existing keys" do
      ctx = %Axn.Context{assigns: %{theme: "light", locale: "en"}}
      updated_ctx = Axn.Context.assign(ctx, %{theme: "dark"})

      assert updated_ctx.assigns == %{theme: "dark", locale: "en"}
    end
  end

  describe "Axn.Context.assign/2 with keyword list" do
    test "assigns multiple key-value pairs from keyword list" do
      ctx = %Axn.Context{}
      updated_ctx = Axn.Context.assign(ctx, current_user: %{id: 123}, theme: "dark")

      assert updated_ctx.assigns == %{current_user: %{id: 123}, theme: "dark"}
    end

    test "merges with existing assignments" do
      ctx = %Axn.Context{assigns: %{locale: "en"}}
      updated_ctx = Axn.Context.assign(ctx, current_user: %{id: 123}, theme: "dark")

      assert updated_ctx.assigns == %{locale: "en", current_user: %{id: 123}, theme: "dark"}
    end

    test "overwrites existing keys" do
      ctx = %Axn.Context{assigns: %{theme: "light", locale: "en"}}
      updated_ctx = Axn.Context.assign(ctx, theme: "dark")

      assert updated_ctx.assigns == %{theme: "dark", locale: "en"}
    end

    test "works with empty keyword list" do
      ctx = %Axn.Context{assigns: %{existing: "value"}}
      updated_ctx = Axn.Context.assign(ctx, [])

      assert updated_ctx.assigns == %{existing: "value"}
    end
  end

  describe "Axn.Context.put_private/3" do
    test "puts a single key-value pair in private" do
      ctx = %Axn.Context{}
      updated_ctx = Axn.Context.put_private(ctx, :correlation_id, "abc123")

      assert updated_ctx.private == %{correlation_id: "abc123"}
      assert updated_ctx != ctx
    end

    test "updates existing private value" do
      ctx = %Axn.Context{private: %{correlation_id: "abc123"}}
      updated_ctx = Axn.Context.put_private(ctx, :correlation_id, "def456")

      assert updated_ctx.private == %{correlation_id: "def456"}
    end

    test "preserves other private values" do
      ctx = %Axn.Context{private: %{changeset: %{}, correlation_id: "abc123"}}
      updated_ctx = Axn.Context.put_private(ctx, :raw_params, %{"name" => "John"})

      assert updated_ctx.private == %{
               changeset: %{},
               correlation_id: "abc123",
               raw_params: %{"name" => "John"}
             }
    end
  end

  describe "Axn.Context.get_private/2" do
    test "gets existing private value" do
      ctx = %Axn.Context{private: %{correlation_id: "abc123", changeset: %{}}}

      assert Axn.Context.get_private(ctx, :correlation_id) == "abc123"
      assert Axn.Context.get_private(ctx, :changeset) == %{}
    end

    test "returns nil for non-existent key" do
      ctx = %Axn.Context{private: %{existing: "value"}}

      assert Axn.Context.get_private(ctx, :non_existent) == nil
    end

    test "returns nil for empty private map" do
      ctx = %Axn.Context{}

      assert Axn.Context.get_private(ctx, :any_key) == nil
    end
  end

  describe "Axn.Context.get_private/3" do
    test "gets existing private value ignoring default" do
      ctx = %Axn.Context{private: %{correlation_id: "abc123"}}

      assert Axn.Context.get_private(ctx, :correlation_id, "default") == "abc123"
    end

    test "returns default for non-existent key" do
      ctx = %Axn.Context{private: %{existing: "value"}}

      assert Axn.Context.get_private(ctx, :non_existent, "my_default") == "my_default"
      assert Axn.Context.get_private(ctx, :non_existent, :atom_default) == :atom_default
      assert Axn.Context.get_private(ctx, :non_existent, nil) == nil
    end

    test "returns default for empty private map" do
      ctx = %Axn.Context{}

      assert Axn.Context.get_private(ctx, :any_key, "default_value") == "default_value"
    end
  end

  describe "Axn.Context.put_params/2" do
    test "sets params" do
      ctx = %Axn.Context{}
      updated_ctx = Axn.Context.put_params(ctx, %{name: "John", age: 25})

      assert updated_ctx.params == %{name: "John", age: 25}
      assert updated_ctx != ctx
    end

    test "replaces existing params completely" do
      ctx = %Axn.Context{params: %{old_param: "value"}}
      updated_ctx = Axn.Context.put_params(ctx, %{name: "John", age: 25})

      assert updated_ctx.params == %{name: "John", age: 25}
      refute Map.has_key?(updated_ctx.params, :old_param)
    end
  end

  describe "Axn.Context.put_result/2" do
    test "sets result" do
      ctx = %Axn.Context{}
      updated_ctx = Axn.Context.put_result(ctx, {:ok, %{id: 123}})

      assert updated_ctx.result == {:ok, %{id: 123}}
      assert updated_ctx != ctx
    end

    test "replaces existing result" do
      ctx = %Axn.Context{result: {:error, "old error"}}
      updated_ctx = Axn.Context.put_result(ctx, {:ok, "success"})

      assert updated_ctx.result == {:ok, "success"}
    end
  end
end
