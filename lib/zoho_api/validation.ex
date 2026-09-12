defmodule ZohoAPI.Validation do
  @moduledoc """
  Input validation helpers for Zoho API requests.

  Provides validation functions to prevent common security issues
  like path injection attacks.
  """

  @doc """
  Validates that an ID is safe to use in URL paths.

  IDs must be alphanumeric with optional underscores and hyphens.
  Path traversal characters (..) and path separators (/, \\) are rejected.

  ## Examples

      iex> Validation.validate_id("12345")
      :ok

      iex> Validation.validate_id("abc_123-xyz")
      :ok

      iex> Validation.validate_id("../admin")
      {:error, "Invalid ID: path traversal not allowed"}

      iex> Validation.validate_id("")
      {:error, "ID cannot be empty"}
  """
  @spec validate_id(String.t()) :: :ok | {:error, String.t()}
  def validate_id(id) when is_binary(id) do
    cond do
      String.trim(id) == "" ->
        {:error, "ID cannot be empty"}

      String.contains?(id, "..") ->
        {:error, "Invalid ID: path traversal not allowed"}

      String.contains?(id, "/") ->
        {:error, "Invalid ID: path separators not allowed"}

      String.contains?(id, "\\") ->
        {:error, "Invalid ID: path separators not allowed"}

      not Regex.match?(~r/^[\w\-]+$/, id) ->
        {:error, "Invalid ID: must contain only alphanumeric characters, underscores, or hyphens"}

      true ->
        :ok
    end
  end

  def validate_id(_), do: {:error, "ID must be a string"}

  @doc """
  Validates a value used as a URL path segment when it may be an email
  address rather than a bare alphanumeric ID.

  `validate_id/1`'s `^[\\w\\-]+$` regex rejects the `@` and `.` an email
  address needs, so it cannot guard a path built from one. This validates the
  same path-injection risk (traversal, separators, and the query/fragment
  delimiters `?`/`#`, which would let a crafted value redirect the request to
  an unintended path or smuggle query params) without constraining the
  charset otherwise — any non-empty, whitespace-free value with no path or
  URL-structural characters passes.

  ## Examples

      iex> Validation.validate_path_segment("person@example.com")
      :ok

      iex> Validation.validate_path_segment("987000000654321")
      :ok

      iex> Validation.validate_path_segment("../admin")
      {:error, "Invalid value: path traversal not allowed"}

      iex> Validation.validate_path_segment("")
      {:error, "value cannot be empty"}
  """
  @spec validate_path_segment(String.t()) :: :ok | {:error, String.t()}
  def validate_path_segment(value) when is_binary(value) do
    cond do
      String.trim(value) == "" ->
        {:error, "value cannot be empty"}

      String.contains?(value, "..") ->
        {:error, "Invalid value: path traversal not allowed"}

      String.contains?(value, "/") or String.contains?(value, "\\") ->
        {:error, "Invalid value: path separators not allowed"}

      String.contains?(value, "?") or String.contains?(value, "#") ->
        {:error, "Invalid value: query/fragment separators not allowed"}

      Regex.match?(~r/\s/, value) ->
        {:error, "Invalid value: whitespace not allowed"}

      true ->
        :ok
    end
  end

  def validate_path_segment(_), do: {:error, "value must be a string"}
end
