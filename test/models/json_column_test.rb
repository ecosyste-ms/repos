require "test_helper"

class JsonColumnTest < ActiveSupport::TestCase
  # Regression: json 3.0.0 made JSON.parse kwargs-only; activesupport <= 8.1.3.1
  # still passes a positional opts hash from ActiveSupport::JSON.decode, so every
  # ActiveRecord json column read raised ArgumentError. rails/rails#58601 fixes
  # decode; until that ships json is pinned < 3 in the Gemfile.

  test "ActiveRecord json type deserializes a raw string" do
    assert_equal({ "funding" => { "github" => "foo" } },
                 ActiveRecord::Type::Json.new.deserialize('{"funding":{"github":"foo"}}'))
  end

  test "Repository#metadata round-trips through the database" do
    repo = create(:repository, metadata: { "funding" => { "github" => "foo" } })
    assert_equal({ "github" => "foo" }, repo.reload.metadata["funding"])
  end
end
