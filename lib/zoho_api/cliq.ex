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
          {:ok, %{users: resp["users"] || [], next_token: resp["next_token"]}}

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

  @doc """
  Adds members to a Cliq channel.

  ## Parameters
    - `channel_id` - The numeric channel ID string.
    - `user_ids` - List of Zoho user ID strings to add.
  """
  @spec add_channel_members(String.t(), [String.t()]) :: {:ok, map()} | {:error, any()}
  def add_channel_members(channel_id, user_ids) do
    with {:ok, token} <- TokenCache.get_or_refresh(:cliq) do
      Request.new("cliq")
      |> Request.set_access_token(token)
      |> Request.with_version(@cliq_version)
      |> Request.with_method(:post)
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

  # ---------------------------------------------------------------------------
  # Private pagination helpers
  # ---------------------------------------------------------------------------

  defp collect_pages(fetch_fn, key) do
    do_collect_pages(fetch_fn, nil, [], key)
  end

  # `acc` accumulates one list per page in reverse page order so each step is
  # O(1); the pages are flattened back into request order once at the terminal
  # case. Avoids the O(n²) blowup of `acc ++ items` on many-page responses.
  defp do_collect_pages(fetch_fn, token, acc, key) do
    case fetch_fn.(token) do
      {:ok, resp} ->
        items = Map.get(resp, key, [])
        next = Map.get(resp, :next_token)
        acc = [items | acc]

        if next && next != "" do
          do_collect_pages(fetch_fn, next, acc, key)
        else
          {:ok, acc |> Enum.reverse() |> Enum.concat()}
        end

      {:error, _} = err ->
        err
    end
  end
end
