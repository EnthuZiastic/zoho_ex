defmodule ZohoAPI.ValidationTest do
  use ExUnit.Case, async: true

  alias ZohoAPI.Validation

  describe "validate_id/1" do
    test "accepts valid alphanumeric IDs" do
      assert :ok = Validation.validate_id("12345")
      assert :ok = Validation.validate_id("abc123")
      assert :ok = Validation.validate_id("ABC123xyz")
    end

    test "accepts IDs with underscores and hyphens" do
      assert :ok = Validation.validate_id("abc_123")
      assert :ok = Validation.validate_id("abc-123")
      assert :ok = Validation.validate_id("abc_123-xyz")
    end

    test "rejects path traversal attempts" do
      assert {:error, "Invalid ID: path traversal not allowed"} =
               Validation.validate_id("../admin")

      assert {:error, "Invalid ID: path traversal not allowed"} =
               Validation.validate_id("..\\admin")

      assert {:error, "Invalid ID: path traversal not allowed"} =
               Validation.validate_id("foo/../bar")
    end

    test "rejects IDs with path separators" do
      assert {:error, "Invalid ID: path separators not allowed"} =
               Validation.validate_id("foo/bar")

      assert {:error, "Invalid ID: path separators not allowed"} =
               Validation.validate_id("foo\\bar")
    end

    test "rejects empty IDs" do
      assert {:error, "ID cannot be empty"} = Validation.validate_id("")
      assert {:error, "ID cannot be empty"} = Validation.validate_id("   ")
    end

    test "rejects IDs with special characters" do
      assert {:error, _} = Validation.validate_id("id@123")
      assert {:error, _} = Validation.validate_id("id#123")
      assert {:error, _} = Validation.validate_id("id$123")
      assert {:error, _} = Validation.validate_id("id%123")
    end

    test "rejects non-string IDs" do
      assert {:error, "ID must be a string"} = Validation.validate_id(123)
      assert {:error, "ID must be a string"} = Validation.validate_id(nil)
      assert {:error, "ID must be a string"} = Validation.validate_id(%{})
    end
  end

  describe "validate_path_segment/1" do
    test "accepts email addresses" do
      assert :ok = Validation.validate_path_segment("person@example.com")
      assert :ok = Validation.validate_path_segment("first.last+tag@sub.example.co.in")
    end

    test "accepts plain alphanumeric IDs (ZUIDs)" do
      assert :ok = Validation.validate_path_segment("987000000654321")
    end

    test "rejects path traversal attempts" do
      assert {:error, "Invalid value: path traversal not allowed"} =
               Validation.validate_path_segment("../admin")
    end

    test "rejects values with path separators" do
      assert {:error, "Invalid value: path separators not allowed"} =
               Validation.validate_path_segment("foo/bar@example.com")

      assert {:error, "Invalid value: path separators not allowed"} =
               Validation.validate_path_segment("foo\\bar")
    end

    test "rejects values with query or fragment delimiters" do
      assert {:error, "Invalid value: query/fragment separators not allowed"} =
               Validation.validate_path_segment("person@example.com?x=1")

      assert {:error, "Invalid value: query/fragment separators not allowed"} =
               Validation.validate_path_segment("person@example.com#frag")
    end

    test "rejects whitespace" do
      assert {:error, "Invalid value: whitespace not allowed"} =
               Validation.validate_path_segment("person @example.com")
    end

    test "rejects empty values" do
      assert {:error, "value cannot be empty"} = Validation.validate_path_segment("")
      assert {:error, "value cannot be empty"} = Validation.validate_path_segment("   ")
    end

    test "rejects non-string values" do
      assert {:error, "value must be a string"} = Validation.validate_path_segment(123)
      assert {:error, "value must be a string"} = Validation.validate_path_segment(nil)
    end
  end
end
