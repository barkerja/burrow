defmodule Burrow.ULIDTest do
  use ExUnit.Case, async: true

  alias Burrow.ULID

  describe "generate/0" do
    test "returns a 26 character string" do
      ulid = ULID.generate()
      assert String.length(ulid) == 26
    end

    test "returns valid Crockford Base32 characters" do
      ulid = ULID.generate()
      assert String.match?(ulid, ~r/^[0-9A-HJKMNP-TV-Z]{26}$/)
    end

    test "generates unique values" do
      ulids = for _ <- 1..100, do: ULID.generate()
      assert length(Enum.uniq(ulids)) == 100
    end

    test "generates lexicographically sortable values over time" do
      ulid1 = ULID.generate()
      Process.sleep(2)
      ulid2 = ULID.generate()
      assert ulid1 < ulid2
    end
  end

  describe "generate/1" do
    test "generates ULID with specific timestamp" do
      timestamp = 1_700_000_000_000
      ulid = ULID.generate(timestamp)

      assert String.length(ulid) == 26
      assert ULID.valid?(ulid)
    end

    test "same timestamp produces different ULIDs due to randomness" do
      timestamp = 1_700_000_000_000
      ulid1 = ULID.generate(timestamp)
      ulid2 = ULID.generate(timestamp)

      # First 10 chars (timestamp) should be same
      assert String.slice(ulid1, 0, 10) == String.slice(ulid2, 0, 10)
      # Last 16 chars (random) should differ
      assert String.slice(ulid1, 10, 16) != String.slice(ulid2, 10, 16)
    end

    test "accepts zero timestamp" do
      ulid = ULID.generate(0)
      assert ULID.valid?(ulid)
      assert ULID.timestamp(ulid) == 0
    end
  end

  describe "timestamp/1" do
    test "extracts timestamp from ULID" do
      timestamp = 1_700_000_000_000
      ulid = ULID.generate(timestamp)
      extracted = ULID.timestamp(ulid)

      assert extracted == timestamp
    end

    test "extracts current timestamp approximately" do
      before = System.system_time(:millisecond)
      ulid = ULID.generate()
      after_time = System.system_time(:millisecond)

      extracted = ULID.timestamp(ulid)
      assert extracted >= before
      assert extracted <= after_time
    end

    test "handles lowercase input" do
      ulid = ULID.generate()
      lower = String.downcase(ulid)

      assert ULID.timestamp(lower) == ULID.timestamp(ulid)
    end
  end

  describe "valid?/1" do
    test "returns true for valid ULID" do
      assert ULID.valid?("01ARZ3NDEKTSV4RRFFQ69G5FAV")
    end

    test "returns true for lowercase valid ULID" do
      assert ULID.valid?("01arz3ndektsv4rrffq69g5fav")
    end

    test "returns true for generated ULID" do
      ulid = ULID.generate()
      assert ULID.valid?(ulid)
    end

    test "returns false for wrong length" do
      refute ULID.valid?("01ARZ3NDEKTSV4RRFFQ69G5FA")
      refute ULID.valid?("01ARZ3NDEKTSV4RRFFQ69G5FAVX")
    end

    test "returns false for invalid characters" do
      # I, L, O, U are not in Crockford Base32
      refute ULID.valid?("01ARZ3NDIKTSV4RRFFQ69G5FAV")
      refute ULID.valid?("01ARZ3NDLKTSV4RRFFQ69G5FAV")
      refute ULID.valid?("01ARZ3NDOKTSV4RRFFQ69G5FAV")
      refute ULID.valid?("01ARZ3NDUKTSV4RRFFQ69G5FAV")
    end

    test "returns false for nil" do
      refute ULID.valid?(nil)
    end

    test "returns false for non-string" do
      refute ULID.valid?(123)
      refute ULID.valid?(%{})
    end

    test "returns false for empty string" do
      refute ULID.valid?("")
    end
  end

  describe "encoding consistency" do
    test "known timestamp encodes correctly" do
      # Timestamp 0 should produce all zeros for first 10 chars
      ulid = ULID.generate(0)
      assert String.slice(ulid, 0, 10) == "0000000000"
    end

    test "max 48-bit timestamp is handled" do
      max_ts = 0xFFFFFFFFFFFF
      ulid = ULID.generate(max_ts)

      assert ULID.valid?(ulid)
      assert ULID.timestamp(ulid) == max_ts
    end
  end
end
