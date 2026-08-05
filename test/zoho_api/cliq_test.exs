defmodule ZohoAPI.CliqTest do
  use ExUnit.Case, async: false

  import Mox

  alias ZohoAPI.Cliq
  alias ZohoAPI.TokenCache

  setup :verify_on_exit!

  setup do
    name = :"cliq_test_#{:rand.uniform(100_000)}"
    {:ok, pid} = TokenCache.start_link(name: name)

    prev_config = Application.get_env(:zoho_api, :token_cache, [])
    Application.put_env(:zoho_api, :token_cache, name: name)

    on_exit(fn ->
      Application.put_env(:zoho_api, :token_cache, prev_config)
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    TokenCache.put_token(:cliq, "test_cliq_token")
    assert TokenCache.get_token(:cliq) == "test_cliq_token"

    :ok
  end

  # ---------------------------------------------------------------------------
  # list_all_channels/0
  # ---------------------------------------------------------------------------

  describe "list_all_channels/0" do
    test "collects channels from a single page when next_token is absent" do
      expect(ZohoAPI.HTTPClientMock, :request, fn :get, url, _body, _headers, _opts ->
        assert url =~ "channels"
        refute url =~ "next_token"

        {:ok,
         %Req.Response{
           status: 200,
           body:
             Jason.encode!(%{
               "channels" => [
                 %{"channel_id" => "111", "name" => "#General"},
                 %{"channel_id" => "222", "name" => "#Random"}
               ]
             })
         }}
      end)

      assert {:ok, channels} = Cliq.list_all_channels()
      assert length(channels) == 2
      assert Enum.any?(channels, &(&1["channel_id"] == "111"))
    end

    test "follows next_token across multiple pages until exhausted" do
      # Page 1 — returns next_token
      expect(ZohoAPI.HTTPClientMock, :request, fn :get, url, _body, _headers, _opts ->
        refute url =~ "next_token"

        {:ok,
         %Req.Response{
           status: 200,
           body:
             Jason.encode!(%{
               "channels" => [%{"channel_id" => "111"}],
               "next_token" => "page2token"
             })
         }}
      end)

      # Page 2 — no next_token
      expect(ZohoAPI.HTTPClientMock, :request, fn :get, url, _body, _headers, _opts ->
        assert url =~ "next_token=page2token"

        {:ok,
         %Req.Response{
           status: 200,
           body:
             Jason.encode!(%{
               "channels" => [%{"channel_id" => "222"}]
             })
         }}
      end)

      assert {:ok, channels} = Cliq.list_all_channels()
      assert length(channels) == 2
      assert Enum.map(channels, & &1["channel_id"]) == ["111", "222"]
    end

    test "returns error immediately if a page fetch fails" do
      expect(ZohoAPI.HTTPClientMock, :request, fn :get, _url, _body, _headers, _opts ->
        {:ok, %Req.Response{status: 500, body: Jason.encode!(%{"message" => "server error"})}}
      end)

      assert {:error, _} = Cliq.list_all_channels()
    end

    # The three tests below encode what Cliq ACTUALLY does. The two happy-path tests
    # above model a last page that omits next_token — Cliq never does that, which is
    # why an infinite pagination loop shipped past a green suite.

    test "terminates on the empty page even though it still carries a next_token" do
      # Page 1 — real rows, plus a token.
      expect(ZohoAPI.HTTPClientMock, :request, fn :get, _url, _body, _headers, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body:
             Jason.encode!(%{
               "channels" => [%{"channel_id" => "111"}],
               "next_token" => "tail_token"
             })
         }}
      end)

      # Page 2 — zero rows, and Cliq repeats the SAME token forever.
      expect(ZohoAPI.HTTPClientMock, :request, fn :get, url, _body, _headers, _opts ->
        assert url =~ "next_token=tail_token"

        {:ok,
         %Req.Response{
           status: 200,
           body: Jason.encode!(%{"channels" => [], "next_token" => "tail_token"})
         }}
      end)

      # Exactly two calls are expected; a third would fail verify_on_exit!.
      assert {:ok, channels} = Cliq.list_all_channels()
      assert Enum.map(channels, & &1["channel_id"]) == ["111"]
    end

    test "keeps paging when has_more is false but rows and a token are still coming" do
      # Cliq reports has_more=false on page 1 of a multi-page list, so it must not be
      # used as the stop signal — doing so truncates the result to the first page.
      expect(ZohoAPI.HTTPClientMock, :request, fn :get, _url, _body, _headers, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body:
             Jason.encode!(%{
               "channels" => [%{"channel_id" => "111"}],
               "has_more" => false,
               "next_token" => "p2"
             })
         }}
      end)

      expect(ZohoAPI.HTTPClientMock, :request, fn :get, url, _body, _headers, _opts ->
        assert url =~ "next_token=p2"

        {:ok,
         %Req.Response{
           status: 200,
           body: Jason.encode!(%{"channels" => [], "has_more" => false, "next_token" => "p2"})
         }}
      end)

      assert {:ok, channels} = Cliq.list_all_channels()
      assert Enum.map(channels, & &1["channel_id"]) == ["111"]
    end

    test "errors rather than returning a partial list when the page cap is exceeded" do
      # Never-empty pages with an ever-changing token: only the cap can stop this.
      # It must NOT resolve to {:ok, partial} — callers tombstone anything absent from
      # the returned set, so a truncated list would delete the unfetched remainder.
      stub(ZohoAPI.HTTPClientMock, :request, fn :get, _url, _body, _headers, _opts ->
        token = "tok_#{System.unique_integer([:positive, :monotonic])}"

        {:ok,
         %Req.Response{
           status: 200,
           body:
             Jason.encode!(%{
               "channels" => [%{"channel_id" => "c"}],
               "next_token" => token
             })
         }}
      end)

      assert {:error, {:pagination_cap_exceeded, :channels, 200}} = Cliq.list_all_channels()
    end
  end

  # ---------------------------------------------------------------------------
  # create_channel/1
  # ---------------------------------------------------------------------------

  describe "create_channel/1" do
    test "sends POST to /channels with the provided attrs" do
      attrs = %{name: "engineering", level: "organization", user_ids: ["u1", "u2"]}

      expect(ZohoAPI.HTTPClientMock, :request, fn :post, url, body, _headers, _opts ->
        assert url =~ "/channels"
        refute url =~ "/channels/"

        decoded = Jason.decode!(body)
        assert decoded["name"] == "engineering"
        assert decoded["level"] == "organization"
        assert decoded["user_ids"] == ["u1", "u2"]

        {:ok,
         %Req.Response{
           status: 200,
           body:
             Jason.encode!(%{
               "channel_id" => "987000000654321",
               "name" => "engineering",
               "status" => "created"
             })
         }}
      end)

      assert {:ok, resp} = Cliq.create_channel(attrs)
      assert resp["channel_id"] == "987000000654321"
    end
  end

  # ---------------------------------------------------------------------------
  # add_channel_members/2
  # ---------------------------------------------------------------------------

  describe "add_channel_members/2" do
    test "sends POST to /channels/:id/members with user_ids body key" do
      channel_id = "987000000654321"
      user_ids = ["u1", "u2", "u3"]

      expect(ZohoAPI.HTTPClientMock, :request, fn :post, url, body, _headers, _opts ->
        assert url =~ "channels/#{channel_id}/members"

        decoded = Jason.decode!(body)
        # Key must be "user_ids", not "member_ids"
        assert decoded["user_ids"] == user_ids
        refute Map.has_key?(decoded, "member_ids")

        {:ok,
         %Req.Response{
           status: 200,
           body: Jason.encode!(%{"added" => true})
         }}
      end)

      assert {:ok, %{"added" => true}} = Cliq.add_channel_members(channel_id, user_ids)
    end
  end

  # ---------------------------------------------------------------------------
  # remove_channel_members/2
  # ---------------------------------------------------------------------------

  describe "remove_channel_members/2" do
    test "sends DELETE to /channels/:id/members with user_ids body key" do
      channel_id = "987000000654321"
      user_ids = ["u1"]

      expect(ZohoAPI.HTTPClientMock, :request, fn :delete, url, body, _headers, _opts ->
        assert url =~ "channels/#{channel_id}/members"

        decoded = Jason.decode!(body)
        assert decoded["user_ids"] == user_ids

        {:ok,
         %Req.Response{
           status: 200,
           body: Jason.encode!(%{"removed" => true})
         }}
      end)

      assert {:ok, _} = Cliq.remove_channel_members(channel_id, user_ids)
    end
  end

  # ---------------------------------------------------------------------------
  # delete_channel/1
  # ---------------------------------------------------------------------------

  describe "delete_channel/1" do
    test "returns :ok on 204-equivalent success" do
      channel_id = "987000000654321"

      expect(ZohoAPI.HTTPClientMock, :request, fn :delete, url, _body, _headers, _opts ->
        assert url =~ "channels/#{channel_id}"
        refute url =~ "/members"

        {:ok, %Req.Response{status: 200, body: ""}}
      end)

      assert :ok = Cliq.delete_channel(channel_id)
    end
  end

  # ---------------------------------------------------------------------------
  # archive_channel/1
  # ---------------------------------------------------------------------------

  describe "archive_channel/1" do
    test "sends POST to /channels/:id/archive" do
      channel_id = "987000000654321"

      expect(ZohoAPI.HTTPClientMock, :request, fn :post, url, _body, _headers, _opts ->
        assert url =~ "channels/#{channel_id}/archive"

        {:ok,
         %Req.Response{
           status: 200,
           body: Jason.encode!(%{"status" => "archived"})
         }}
      end)

      assert {:ok, %{"status" => "archived"}} = Cliq.archive_channel(channel_id)
    end
  end

  # ---------------------------------------------------------------------------
  # update_member_role/3
  # ---------------------------------------------------------------------------

  describe "update_member_role/3" do
    test "sends PUT to /channels/:channel_id/members/:user_id with role body" do
      channel_id = "987000000654321"
      user_id = "u1"

      expect(ZohoAPI.HTTPClientMock, :request, fn :put, url, body, _headers, _opts ->
        assert url =~ "channels/#{channel_id}/members/#{user_id}"

        decoded = Jason.decode!(body)
        assert decoded["role"] == "admin"

        {:ok,
         %Req.Response{
           status: 200,
           body: Jason.encode!(%{"updated" => true})
         }}
      end)

      assert {:ok, _} = Cliq.update_member_role(channel_id, user_id, "admin")
    end
  end

  # ---------------------------------------------------------------------------
  # update_channel/2
  # ---------------------------------------------------------------------------

  describe "update_channel/2" do
    test "sends PUT to /channels/:id with only allowed keys" do
      channel_id = "987000000654321"

      expect(ZohoAPI.HTTPClientMock, :request, fn :put, url, body, _headers, _opts ->
        assert url =~ "channels/#{channel_id}"
        refute url =~ "/members"

        decoded = Jason.decode!(body)
        assert decoded["name"] == "engineering"
        assert decoded["description"] == "Eng chatter"

        {:ok,
         %Req.Response{
           status: 200,
           body: Jason.encode!(%{"channel_id" => channel_id, "name" => "engineering"})
         }}
      end)

      attrs = %{name: "engineering", description: "Eng chatter"}
      assert {:ok, resp} = Cliq.update_channel(channel_id, attrs)
      assert resp["channel_id"] == channel_id
    end

    test "drops :level and any unknown keys from the body" do
      channel_id = "987000000654321"

      expect(ZohoAPI.HTTPClientMock, :request, fn :put, _url, body, _headers, _opts ->
        decoded = Jason.decode!(body)
        # Access level is immutable after create — must never be forwarded.
        assert decoded["name"] == "engineering"
        refute Map.has_key?(decoded, "level")
        refute Map.has_key?(decoded, "foo")
        refute Map.has_key?(decoded, "user_ids")

        {:ok, %Req.Response{status: 200, body: Jason.encode!(%{"updated" => true})}}
      end)

      attrs = %{name: "engineering", level: "organization", foo: "bar", user_ids: ["u1"]}
      assert {:ok, _} = Cliq.update_channel(channel_id, attrs)
    end

    test "normalizes string-keyed attrs into the body" do
      channel_id = "987000000654321"

      expect(ZohoAPI.HTTPClientMock, :request, fn :put, _url, body, _headers, _opts ->
        decoded = Jason.decode!(body)
        assert decoded["name"] == "engineering"
        assert decoded["description"] == "Eng chatter"
        refute Map.has_key?(decoded, "level")

        {:ok, %Req.Response{status: 200, body: Jason.encode!(%{"updated" => true})}}
      end)

      # String keys must not be silently dropped (would produce an empty PUT).
      attrs = %{
        "name" => "engineering",
        "description" => "Eng chatter",
        "level" => "organization"
      }

      assert {:ok, _} = Cliq.update_channel(channel_id, attrs)
    end

    test "returns :no_updatable_fields and makes no request when no accepted keys" do
      # No expect/1 is set — verify_on_exit! asserts the HTTP client is never
      # called, proving the guard short-circuits before hitting the API.
      assert {:error, :no_updatable_fields} =
               Cliq.update_channel("987000000654321", %{level: "organization", foo: "bar"})

      assert {:error, :no_updatable_fields} =
               Cliq.update_channel("987000000654321", %{})
    end
  end

  # ---------------------------------------------------------------------------
  # unarchive_channel/1
  # ---------------------------------------------------------------------------

  describe "unarchive_channel/1" do
    test "sends POST to /channels/:id/unarchive" do
      channel_id = "987000000654321"

      expect(ZohoAPI.HTTPClientMock, :request, fn :post, url, _body, _headers, _opts ->
        assert url =~ "channels/#{channel_id}/unarchive"

        {:ok,
         %Req.Response{
           status: 200,
           body: Jason.encode!(%{"status" => "unarchived"})
         }}
      end)

      assert {:ok, %{"status" => "unarchived"}} = Cliq.unarchive_channel(channel_id)
    end
  end

  # ---------------------------------------------------------------------------
  # list_all_channel_members/1
  # ---------------------------------------------------------------------------

  describe "list_all_channel_members/1" do
    test "fetches all member pages for a given channel_id" do
      channel_id = "987000000654321"

      expect(ZohoAPI.HTTPClientMock, :request, fn :get, url, _body, _headers, _opts ->
        assert url =~ "channels/#{channel_id}/members"

        {:ok,
         %Req.Response{
           status: 200,
           body:
             Jason.encode!(%{
               "members" => [%{"user_id" => "u1"}, %{"user_id" => "u2"}]
             })
         }}
      end)

      assert {:ok, members} = Cliq.list_all_channel_members(channel_id)
      assert length(members) == 2
    end
  end

  # ---------------------------------------------------------------------------
  # list_all_users/0
  # ---------------------------------------------------------------------------

  describe "list_all_users/0" do
    test "falls back to the legacy \"users\" key, collecting across pages" do
      expect(ZohoAPI.HTTPClientMock, :request, fn :get, url, _body, _headers, _opts ->
        assert url =~ "/users"

        {:ok,
         %Req.Response{
           status: 200,
           body:
             Jason.encode!(%{
               "users" => [%{"user_id" => "u1"}, %{"user_id" => "u2"}],
               "next_token" => "tok2"
             })
         }}
      end)

      expect(ZohoAPI.HTTPClientMock, :request, fn :get, url, _body, _headers, _opts ->
        assert url =~ "next_token=tok2"

        {:ok,
         %Req.Response{
           status: 200,
           body:
             Jason.encode!(%{
               "users" => [%{"user_id" => "u3"}]
             })
         }}
      end)

      assert {:ok, users} = Cliq.list_all_users()
      assert length(users) == 3
    end

    test "reads rows from the \"data\" key that Cliq actually returns" do
      # Live response keys are ["data", "has_more", "url"] — there is no "users" key.
      # Reading "users" yielded [] on every call, which is indistinguishable from an
      # empty organisation, so the user sync reported success having written nothing.
      expect(ZohoAPI.HTTPClientMock, :request, fn :get, url, _body, _headers, _opts ->
        assert url =~ "/users"

        {:ok,
         %Req.Response{
           status: 200,
           body:
             Jason.encode!(%{
               "data" => [%{"id" => "u1"}, %{"id" => "u2"}],
               "has_more" => false,
               "url" => "/api/v2/users"
             })
         }}
      end)

      assert {:ok, users} = Cliq.list_all_users()
      assert Enum.map(users, & &1["id"]) == ["u1", "u2"]
    end
  end

  # ---------------------------------------------------------------------------
  # list_all_teams/0
  # ---------------------------------------------------------------------------

  describe "list_all_teams/0" do
    test "collects teams from a single page when next_token is absent" do
      expect(ZohoAPI.HTTPClientMock, :request, fn :get, url, _body, _headers, _opts ->
        assert url =~ "/teams"
        refute url =~ "next_token"

        {:ok,
         %Req.Response{
           status: 200,
           body:
             Jason.encode!(%{
               "teams" => [
                 %{"team_id" => "60012343427", "name" => "Operations"},
                 %{"team_id" => "60012343999", "name" => "Sales"}
               ]
             })
         }}
      end)

      assert {:ok, teams} = Cliq.list_all_teams()
      assert length(teams) == 2
      assert Enum.any?(teams, &(&1["team_id"] == "60012343427"))
    end

    test "follows next_token across multiple pages until exhausted" do
      expect(ZohoAPI.HTTPClientMock, :request, fn :get, url, _body, _headers, _opts ->
        refute url =~ "next_token"

        {:ok,
         %Req.Response{
           status: 200,
           body:
             Jason.encode!(%{
               "teams" => [%{"team_id" => "t1"}],
               "next_token" => "teampage2"
             })
         }}
      end)

      expect(ZohoAPI.HTTPClientMock, :request, fn :get, url, _body, _headers, _opts ->
        assert url =~ "next_token=teampage2"

        {:ok,
         %Req.Response{
           status: 200,
           body: Jason.encode!(%{"teams" => [%{"team_id" => "t2"}]})
         }}
      end)

      assert {:ok, teams} = Cliq.list_all_teams()
      assert Enum.map(teams, & &1["team_id"]) == ["t1", "t2"]
    end

    test "returns error immediately if a page fetch fails" do
      expect(ZohoAPI.HTTPClientMock, :request, fn :get, _url, _body, _headers, _opts ->
        {:ok, %Req.Response{status: 500, body: Jason.encode!(%{"message" => "server error"})}}
      end)

      assert {:error, _} = Cliq.list_all_teams()
    end
  end
end
