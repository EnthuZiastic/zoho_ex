defmodule ZohoAPI.Cliq do
  @moduledoc """
  High-level Zoho Cliq client.

  Manages token fetching automatically via `ZohoAPI.TokenCache`.

  ## Examples

      {:ok, result} = ZohoAPI.Cliq.create_message("Hello team!", "general")
      {:ok, channels} = ZohoAPI.Cliq.list_all_channels()
      {:ok, channel} = ZohoAPI.Cliq.get_channel("987000000654321")
  """

  require Logger

  alias ZohoAPI.Request
  alias ZohoAPI.TokenCache
  alias ZohoAPI.Validation

  @cliq_version "v2"

  # Note: This module builds a Request directly rather than going through
  # InputRequest. The Cliq API has no corresponding low-level module in
  # lib/zoho_api/modules/, so there is no InputRequest-based adapter to
  # delegate to. Retry and rate-limiting middleware that operate at the
  # Request level (not InputRequest) still apply.

  # ---------------------------------------------------------------------------
  # Existing: create_message
  # ---------------------------------------------------------------------------

  @spec create_message(String.t(), String.t()) :: {:ok, map()} | {:error, any()}
  def create_message(message, channel_name) do
    with :ok <- Validation.validate_id(channel_name),
         {:ok, token} <- TokenCache.get_or_refresh(:cliq) do
      Request.new("cliq")
      |> Request.set_access_token(token)
      |> Request.with_version(@cliq_version)
      |> Request.with_method(:post)
      |> Request.with_path("channelsbyname/#{channel_name}/message")
      |> Request.with_body(%{text: message})
      |> Request.send()
    end
  end

  # ---------------------------------------------------------------------------
  # Channel read methods
  # ---------------------------------------------------------------------------

  @doc """
  Lists a single page of Cliq channels.

  ## Parameters
    - `next_token` - Pagination token from a previous response, or `nil` for
      the first page.

  ## Returns
    `{:ok, %{channels: [map()], next_token: String.t() | nil}}` on success.
  """
  @spec list_channels(String.t() | nil) ::
          {:ok, %{channels: [map()], next_token: String.t() | nil}} | {:error, any()}
  def list_channels(next_token \\ nil) do
    with {:ok, token} <- TokenCache.get_or_refresh(:cliq) do
      req =
        Request.new("cliq")
        |> Request.set_access_token(token)
        |> Request.with_version(@cliq_version)
        |> Request.with_method(:get)
        |> Request.with_path("channels")

      req =
        if next_token,
          do: Request.with_params(req, %{next_token: next_token}),
          else: req

      case Request.send(req) do
        {:ok, resp} ->
          {:ok, %{channels: resp["channels"] || [], next_token: resp["next_token"]}}

        err ->
          err
      end
    end
  catch
    :exit, {:noproc, {GenServer, :call, [ZohoAPI.TokenCache | _]}} ->
      Logger.warning("[ZohoAPI.Cliq] TokenCache unavailable — skipping")
      {:error, :zoho_token_cache_unavailable}
  end

  @doc """
  Fetches all Cliq channels by following `next_token` pagination until
  exhausted.

  ## Returns
    `{:ok, [map()]}` containing the full list across all pages.

    `{:error, {:pagination_cap_exceeded, :channels, max}}` if pagination ran past
    `max` pages without reaching the end. Handle this explicitly: the result is
    NEVER a partial list, because callers that reconcile absence would tombstone
    everything on the unfetched pages.
  """
  @spec list_all_channels() :: {:ok, [map()]} | {:error, any()}
  def list_all_channels, do: collect_pages(&list_channels/1, :channels)

  @doc """
  Fetches a single channel by its numeric ID string.

  ## Parameters
    - `channel_id` - The numeric channel ID (e.g. `"987000000654321"`).
  """
  @spec get_channel(String.t()) :: {:ok, map()} | {:error, any()}
  def get_channel(channel_id) do
    with {:ok, token} <- TokenCache.get_or_refresh(:cliq) do
      Request.new("cliq")
      |> Request.set_access_token(token)
      |> Request.with_version(@cliq_version)
      |> Request.with_method(:get)
      |> Request.with_path("channels/#{channel_id}")
      |> Request.send()
    end
  catch
    :exit, {:noproc, {GenServer, :call, [ZohoAPI.TokenCache | _]}} ->
      Logger.warning("[ZohoAPI.Cliq] TokenCache unavailable — skipping")
      {:error, :zoho_token_cache_unavailable}
  end

  @doc """
  Lists a single page of members for a channel.

  ## Parameters
    - `channel_id` - The numeric channel ID string.
    - `next_token` - Pagination token, or `nil` for the first page.
  """
  @spec list_channel_members(String.t(), String.t() | nil) ::
          {:ok, %{members: [map()], next_token: String.t() | nil}} | {:error, any()}
  def list_channel_members(channel_id, next_token \\ nil) do
    with {:ok, token} <- TokenCache.get_or_refresh(:cliq) do
      req =
        Request.new("cliq")
        |> Request.set_access_token(token)
        |> Request.with_version(@cliq_version)
        |> Request.with_method(:get)
        |> Request.with_path("channels/#{channel_id}/members")

      req =
        if next_token,
          do: Request.with_params(req, %{next_token: next_token}),
          else: req

      case Request.send(req) do
        {:ok, resp} ->
          {:ok, %{members: resp["members"] || [], next_token: resp["next_token"]}}

        err ->
          err
      end
    end
  catch
    :exit, {:noproc, {GenServer, :call, [ZohoAPI.TokenCache | _]}} ->
      Logger.warning("[ZohoAPI.Cliq] TokenCache unavailable — skipping")
      {:error, :zoho_token_cache_unavailable}
  end

  @doc """
  Fetches all members of a channel by following `next_token` pagination.

  May return `{:error, {:pagination_cap_exceeded, :members, max}}` — see
  `list_all_channels/0` for why that is an error rather than a partial list.
  """
  @spec list_all_channel_members(String.t()) :: {:ok, [map()]} | {:error, any()}
  def list_all_channel_members(channel_id) do
    collect_pages(&list_channel_members(channel_id, &1), :members)
  end

  @doc """
  Lists a single page of Cliq users.

  ## Parameters
    - `next_token` - Pagination token, or `nil` for the first page.
  """
  @spec list_users(String.t() | nil) ::
          {:ok, %{users: [map()], next_token: String.t() | nil}} | {:error, any()}
  def list_users(next_token \\ nil) do
    with {:ok, token} <- TokenCache.get_or_refresh(:cliq) do
      req =
        Request.new("cliq")
        |> Request.set_access_token(token)
        |> Request.with_version(@cliq_version)
        |> Request.with_method(:get)
        |> Request.with_path("users")

      req =
        if next_token,
          do: Request.with_params(req, %{next_token: next_token}),
          else: req

      case Request.send(req) do
        {:ok, resp} ->
          # `GET /users` returns its rows under "data", NOT "users" (verified against a
          # live org: keys are ["data", "has_more", "url"]). Reading "users" alone yields
          # [] on every call, which looks exactly like an empty organisation. "users" is
          # kept as a fallback so a provider-side rename cannot silently re-break this.
          {:ok, %{users: resp["data"] || resp["users"] || [], next_token: resp["next_token"]}}

        err ->
          err
      end
    end
  catch
    :exit, {:noproc, {GenServer, :call, [ZohoAPI.TokenCache | _]}} ->
      Logger.warning("[ZohoAPI.Cliq] TokenCache unavailable — skipping")
      {:error, :zoho_token_cache_unavailable}
  end

  @doc """
  Fetches all Cliq users by following `next_token` pagination until exhausted.

  May return `{:error, {:pagination_cap_exceeded, :users, max}}` — see
  `list_all_channels/0` for why that is an error rather than a partial list.
  """
  @spec list_all_users() :: {:ok, [map()]} | {:error, any()}
  def list_all_users, do: collect_pages(&list_users/1, :users)

  # ---------------------------------------------------------------------------
  # Team read methods
  # ---------------------------------------------------------------------------

  @doc """
  Lists a single page of Cliq teams.

  Teams are the org units backing `level: "team"` channels — a team channel's
  `team_ids` reference these `team_id` values.

  ## Parameters
    - `next_token` - Pagination token from a previous response, or `nil` for
      the first page.

  ## Returns
    `{:ok, %{teams: [map()], next_token: String.t() | nil}}` on success. Callers
    building a team-channel picker rely on `"team_id"` (string), `"name"`, and
    `"is_team_channel_creation_allowed"`; the raw team map may carry additional
    Zoho fields not enumerated here.
  """
  @spec list_teams(String.t() | nil) ::
          {:ok, %{teams: [map()], next_token: String.t() | nil}} | {:error, any()}
  def list_teams(next_token \\ nil) do
    with {:ok, token} <- TokenCache.get_or_refresh(:cliq) do
      req =
        Request.new("cliq")
        |> Request.set_access_token(token)
        |> Request.with_version(@cliq_version)
        |> Request.with_method(:get)
        |> Request.with_path("teams")

      req =
        if next_token,
          do: Request.with_params(req, %{next_token: next_token}),
          else: req

      case Request.send(req) do
        {:ok, resp} ->
          {:ok, %{teams: resp["teams"] || [], next_token: resp["next_token"]}}

        err ->
          err
      end
    end
  catch
    :exit, {:noproc, {GenServer, :call, [ZohoAPI.TokenCache | _]}} ->
      Logger.warning("[ZohoAPI.Cliq] TokenCache unavailable — skipping")
      {:error, :zoho_token_cache_unavailable}
  end

  @doc """
  Fetches all Cliq teams by following `next_token` pagination until exhausted.

  May return `{:error, {:pagination_cap_exceeded, :teams, max}}` — see
  `list_all_channels/0` for why that is an error rather than a partial list.
  """
  @spec list_all_teams() :: {:ok, [map()]} | {:error, any()}
  def list_all_teams, do: collect_pages(&list_teams/1, :teams)

  # ---------------------------------------------------------------------------
  # Channel write methods
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new Cliq channel.

  ## Parameters
    - `attrs` - Map with keys: `:name` (required), `:description`, `:level`,
      `:user_ids` (list of user ID strings).

  ## Returns
    `{:ok, map()}` where the map contains `"channel_id"` — store this as
    `provider_channel_id` in the database.
  """
  @spec create_channel(map()) :: {:ok, map()} | {:error, any()}
  def create_channel(attrs) do
    with {:ok, token} <- TokenCache.get_or_refresh(:cliq) do
      Request.new("cliq")
      |> Request.set_access_token(token)
      |> Request.with_version(@cliq_version)
      |> Request.with_method(:post)
      |> Request.with_path("channels")
      |> Request.with_body(attrs)
      |> Request.send()
    end
  catch
    :exit, {:noproc, {GenServer, :call, [ZohoAPI.TokenCache | _]}} ->
      Logger.warning("[ZohoAPI.Cliq] TokenCache unavailable — skipping")
      {:error, :zoho_token_cache_unavailable}
  end

  @doc """
  Deletes a Cliq channel. Returns 204 No Content on success (mapped to `:ok`).

  ## Parameters
    - `channel_id` - The numeric channel ID string.
  """
  @spec delete_channel(String.t()) :: :ok | {:error, any()}
  def delete_channel(channel_id) do
    with {:ok, token} <- TokenCache.get_or_refresh(:cliq) do
      result =
        Request.new("cliq")
        |> Request.set_access_token(token)
        |> Request.with_version(@cliq_version)
        |> Request.with_method(:delete)
        |> Request.with_path("channels/#{channel_id}")
        |> Request.send()

      case result do
        {:ok, _} -> :ok
        {:error, _} = err -> err
      end
    end
  catch
    :exit, {:noproc, {GenServer, :call, [ZohoAPI.TokenCache | _]}} ->
      Logger.warning("[ZohoAPI.Cliq] TokenCache unavailable — skipping")
      {:error, :zoho_token_cache_unavailable}
  end

  @doc """
  Archives a Cliq channel. Sends a POST with no body.

  ## Parameters
    - `channel_id` - The numeric channel ID string.
  """
  @spec archive_channel(String.t()) :: {:ok, map()} | {:error, any()}
  def archive_channel(channel_id) do
    with {:ok, token} <- TokenCache.get_or_refresh(:cliq) do
      Request.new("cliq")
      |> Request.set_access_token(token)
      |> Request.with_version(@cliq_version)
      |> Request.with_method(:post)
      |> Request.with_path("channels/#{channel_id}/archive")
      |> Request.send()
    end
  catch
    :exit, {:noproc, {GenServer, :call, [ZohoAPI.TokenCache | _]}} ->
      Logger.warning("[ZohoAPI.Cliq] TokenCache unavailable — skipping")
      {:error, :zoho_token_cache_unavailable}
  end

  # Cliq caps a single add-members call at 100 entries, for both body shapes.
  # Exceeding it is rejected by the API rather than silently truncated, so the
  # guard below turns that into a local error instead of a wasted round trip
  # against a 20 req/min budget.
  @max_channel_members_per_call 100

  @doc """
  Adds members to a Cliq channel by Zoho user ID.

  ## Parameters
    - `channel_id` - The numeric channel ID string.
    - `user_ids` - List of Zoho user ID strings to add. Max #{@max_channel_members_per_call}.

  Use `add_channel_members_by_email/2` for people you only have an email for —
  notably EXTERNAL collaborators, who have no Zoho user ID to look up.
  """
  @spec add_channel_members(String.t(), [String.t()]) ::
          {:ok, map()} | {:error, any()}
  def add_channel_members(channel_id, user_ids) do
    post_channel_members(channel_id, %{user_ids: user_ids}, user_ids)
  end

  @doc """
  Adds members to a Cliq channel by EMAIL address.

  Same endpoint as `add_channel_members/2` — only the body key differs
  (`email_ids` rather than `user_ids`); Cliq documents the request body as
  accepting exactly one of the two.

  This is the only way to add someone you cannot resolve to a Zoho user ID.
  External collaborators are the motivating case: Cliq's `/users` directory does
  not list them, so there is no id to look up, and a caller holding only an email
  would otherwise be stuck.

  A SEPARATE function rather than a shape-sniffing clause on
  `add_channel_members/2`: both take a list of strings, so a runtime guess
  between "these are ids" and "these are emails" would have to key on something
  like the presence of `@`. That heuristic fails silently and in the worst
  direction — it would post an id list under `email_ids`, which Cliq accepts as
  a well-formed request that matches nobody.

  ## Parameters
    - `channel_id` - The numeric channel ID string.
    - `email_ids` - List of email address strings. Max #{@max_channel_members_per_call}.
  """
  @spec add_channel_members_by_email(String.t(), [String.t()]) ::
          {:ok, map()} | {:error, any()}
  def add_channel_members_by_email(channel_id, email_ids) do
    post_channel_members(channel_id, %{email_ids: email_ids}, email_ids)
  end

  # Shared transport for both body shapes. `entries` is the same list the body
  # carries, passed separately only so the cap check does not have to know which
  # key was used.
  defp post_channel_members(_channel_id, _body, entries)
       when length(entries) > @max_channel_members_per_call do
    {:error, {:too_many_members, length(entries), @max_channel_members_per_call}}
  end

  defp post_channel_members(channel_id, body, _entries) do
    with {:ok, token} <- TokenCache.get_or_refresh(:cliq) do
      Request.new("cliq")
      |> Request.set_access_token(token)
      |> Request.with_version(@cliq_version)
      |> Request.with_method(:post)
      |> Request.with_path("channels/#{channel_id}/members")
      |> Request.with_body(body)
      |> Request.send()
    end
  catch
    :exit, {:noproc, {GenServer, :call, [ZohoAPI.TokenCache | _]}} ->
      Logger.warning("[ZohoAPI.Cliq] TokenCache unavailable — skipping")
      {:error, :zoho_token_cache_unavailable}
  end

  @doc """
  Removes members from a Cliq channel.

  ## Parameters
    - `channel_id` - The numeric channel ID string.
    - `user_ids` - List of Zoho user ID strings to remove.
  """
  @spec remove_channel_members(String.t(), [String.t()]) :: {:ok, map()} | {:error, any()}
  def remove_channel_members(channel_id, user_ids) do
    with {:ok, token} <- TokenCache.get_or_refresh(:cliq) do
      Request.new("cliq")
      |> Request.set_access_token(token)
      |> Request.with_version(@cliq_version)
      |> Request.with_method(:delete)
      |> Request.with_path("channels/#{channel_id}/members")
      |> Request.with_body(%{user_ids: user_ids})
      |> Request.send()
    end
  catch
    :exit, {:noproc, {GenServer, :call, [ZohoAPI.TokenCache | _]}} ->
      Logger.warning("[ZohoAPI.Cliq] TokenCache unavailable — skipping")
      {:error, :zoho_token_cache_unavailable}
  end

  @doc """
  Updates the role of a channel member.

  ## Parameters
    - `channel_id` - The numeric channel ID string.
    - `user_id` - The Zoho user ID string.
    - `role` - `"admin"` or `"member"`.
  """
  @spec update_member_role(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, any()}
  def update_member_role(channel_id, user_id, role) do
    with {:ok, token} <- TokenCache.get_or_refresh(:cliq) do
      Request.new("cliq")
      |> Request.set_access_token(token)
      |> Request.with_version(@cliq_version)
      |> Request.with_method(:put)
      |> Request.with_path("channels/#{channel_id}/members/#{user_id}")
      |> Request.with_body(%{role: role})
      |> Request.send()
    end
  catch
    :exit, {:noproc, {GenServer, :call, [ZohoAPI.TokenCache | _]}} ->
      Logger.warning("[ZohoAPI.Cliq] TokenCache unavailable — skipping")
      {:error, :zoho_token_cache_unavailable}
  end

  @doc """
  Updates a Cliq channel's mutable attributes.

  Sends a PUT to `channels/{channel_id}`.

  A channel's **access level is immutable after creation** — Cliq's update
  endpoint has no `level` field, so a `:level` key (and any other unknown key)
  is dropped and never forwarded. To change access level you must recreate the
  channel.

  ## Parameters
    - `channel_id` - The numeric channel ID string.
    - `attrs` - Map of attributes to update. Only `name` and `description`
      are accepted; all other keys (including `level` and `user_ids`) are
      ignored. Membership is managed via `add_channel_members/2` and
      `remove_channel_members/2`, not here. Keys may be atoms or strings —
      both forms are normalized. If `attrs` carries none of the accepted keys
      the body would be empty, so this returns `{:error, :no_updatable_fields}`
      without calling the API (Zoho rejects an empty update).

  Doc: https://www.zoho.com/cliq/help/restapi/v2/channels/ ("Update a channel").
  """
  @spec update_channel(String.t(), map()) ::
          {:ok, map()} | {:error, :no_updatable_fields | any()}
  def update_channel(channel_id, attrs) do
    body =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.take(["name", "description"])

    if body == %{} do
      {:error, :no_updatable_fields}
    else
      with {:ok, token} <- TokenCache.get_or_refresh(:cliq) do
        Request.new("cliq")
        |> Request.set_access_token(token)
        |> Request.with_version(@cliq_version)
        |> Request.with_method(:put)
        |> Request.with_path("channels/#{channel_id}")
        |> Request.with_body(body)
        |> Request.send()
      end
    end
  catch
    :exit, {:noproc, {GenServer, :call, [ZohoAPI.TokenCache | _]}} ->
      Logger.warning("[ZohoAPI.Cliq] TokenCache unavailable — skipping")
      {:error, :zoho_token_cache_unavailable}
  end

  @doc """
  Unarchives a Cliq channel. Sends a POST with no body to
  `channels/{channel_id}/unarchive`. Mirrors `archive_channel/1`.

  ## Provenance
  There is no published Zoho doc URL for this route. The path is inferred from:
    - the `admin_permission.unarchive_channel: true` flag present on every
      channel object in live Cliq API responses,
    - the Zoho Cliq MCP exposing an `unarchive_channel` tool, and
    - symmetry with the documented `archive_channel/1`
      (POST `channels/{id}/archive`).

  The path `POST channels/{id}/unarchive` is conventional (mirror of archive),
  not a published/live-tested route.

  ## Parameters
    - `channel_id` - The numeric channel ID string.
  """
  @spec unarchive_channel(String.t()) :: {:ok, map()} | {:error, any()}
  def unarchive_channel(channel_id) do
    with {:ok, token} <- TokenCache.get_or_refresh(:cliq) do
      Request.new("cliq")
      |> Request.set_access_token(token)
      |> Request.with_version(@cliq_version)
      |> Request.with_method(:post)
      |> Request.with_path("channels/#{channel_id}/unarchive")
      |> Request.send()
    end
  catch
    :exit, {:noproc, {GenServer, :call, [ZohoAPI.TokenCache | _]}} ->
      Logger.warning("[ZohoAPI.Cliq] TokenCache unavailable — skipping")
      {:error, :zoho_token_cache_unavailable}
  end

  # ---------------------------------------------------------------------------
  # Private pagination helpers
  # ---------------------------------------------------------------------------

  # Cliq returns a `next_token` on EVERY page, including the empty page past the end —
  # and that last token is the PREVIOUS page's token repeated verbatim. Stopping only on
  # a nil/blank token therefore never terminates. Verified against a live org: pages 1-6
  # returned ~50 channels each, page 7 returned the final 18, and page 8 returned 0
  # channels carrying page 7's token, indefinitely.
  #
  # The response's `has_more` flag is NOT a usable stop signal either — it came back
  # `false` on page 1 of that same 7-page list, so trusting it would truncate the result
  # to the first page. Do not "simplify" this to `has_more`.
  #
  # Terminal condition is an EMPTY page. A repeated token and a hard page cap are
  # backstops so a provider-side change can never reinstate the infinite loop.
  @max_pages 200

  defp collect_pages(fetch_fn, key) do
    do_collect_pages(fetch_fn, nil, [], key, [], 1)
  end

  # `acc` accumulates one list per page in reverse page order so each step is
  # O(1); the pages are flattened back into request order once at the terminal
  # case. Avoids the O(n²) blowup of `acc ++ items` on many-page responses.
  defp do_collect_pages(fetch_fn, token, acc, key, seen, page) do
    case fetch_fn.(token) do
      {:ok, resp} ->
        items = Map.get(resp, key, [])
        next = Map.get(resp, :next_token)

        # The tail page contributes nothing and its token is the previous page's, so it
        # never joins the accumulator — continue_pages/6 only ever sees real rows.
        if items == [],
          do: collected(acc),
          else: continue_pages(fetch_fn, next, [items | acc], key, seen, page)

      {:error, _} = err ->
        err
    end
  end

  # `seen` is a plain list, not a MapSet: it is bounded by @max_pages, so the linear
  # membership check is irrelevant next to an HTTP round trip per element — and MapSet's
  # opaque type leaks a dialyzer warning when passed between these private functions.
  defp continue_pages(fetch_fn, next, acc, key, seen, page) do
    cond do
      is_nil(next) or next == "" -> collected(acc)
      next in seen -> collected(acc)
      page >= @max_pages -> cap_exceeded(key)
      true -> do_collect_pages(fetch_fn, next, acc, key, [next | seen], page + 1)
    end
  end

  # Deliberately an error, not a partial `{:ok, list}`. Callers reconcile absence against
  # the returned set (anything missing is tombstoned), so a silently truncated list would
  # delete every record living on the pages we never fetched. Fail loudly instead.
  defp cap_exceeded(key) do
    Logger.error(
      "[ZohoAPI.Cliq] pagination for #{inspect(key)} exceeded #{@max_pages} pages — " <>
        "refusing to return a partial list"
    )

    {:error, {:pagination_cap_exceeded, key, @max_pages}}
  end

  defp collected(acc), do: {:ok, acc |> Enum.reverse() |> Enum.concat()}
end
