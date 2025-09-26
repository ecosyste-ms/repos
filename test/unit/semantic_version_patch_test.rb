require "test_helper"

class SemanticVersionPatchTest < ActiveSupport::TestCase
  test "should handle leading zeros in pre-release identifiers" do
    v = Semantic::Version.new("1.0.0")

    # Test the identifiers method directly with leading zeros
    result = v.identifiers("0009")
    assert_equal [9], result

    # Test with mixed identifiers
    result = v.identifiers("beta.0009.1")
    assert_equal ["beta", 9, 1], result
  end

  test "should handle comparison of versions with leading zero identifiers" do
    v1 = Semantic::Version.new("1.0.0")
    v2 = Semantic::Version.new("1.0.0")

    # Test compare_pre method which is where the original error occurred
    assert_nothing_raised do
      v1.compare_pre("0008", "0009")
    end

    result = v1.compare_pre("0008", "0009")
    assert_equal(-1, result) # 8 < 9

    result = v1.compare_pre("0009", "0008")
    assert_equal(1, result) # 9 > 8
  end

  test "should preserve original behavior for normal identifiers" do
    v = Semantic::Version.new("1.0.0")

    # Test normal numeric identifiers
    result = v.identifiers("123")
    assert_equal [123], result

    # Test mixed alphanumeric
    result = v.identifiers("alpha.1.beta")
    assert_equal ["alpha", 1, "beta"], result
  end
end