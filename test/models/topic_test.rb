require 'test_helper'

class TopicTest < ActiveSupport::TestCase
  setup do
    @host = create(:host)
  end

  test "validates presence of name" do
    topic = Topic.new(host: @host, name: nil)
    assert_not topic.valid?
    assert_includes topic.errors[:name], "can't be blank"
  end

  test "validates uniqueness of name scoped to host" do
    Topic.create!(host: @host, name: 'ruby')

    duplicate = Topic.new(host: @host, name: 'ruby')
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "allows same topic name on different hosts" do
    other_host = create(:host, name: 'GitLab', url: 'https://gitlab.com')

    Topic.create!(host: @host, name: 'ruby')
    other_topic = Topic.new(host: other_host, name: 'ruby')

    assert other_topic.valid?
  end

  test "repositories returns repos with matching topic array" do
    repo_with_topic = create(:repository, host: @host, topics: ['ruby', 'rails'])
    repo_without_topic = create(:repository, host: @host, topics: ['python'])

    topic = Topic.create!(host: @host, name: 'ruby')

    assert_includes topic.repositories, repo_with_topic
    assert_not_includes topic.repositories, repo_without_topic
  end

  test "sync_for_host creates topics from repository topics arrays" do
    create(:repository, host: @host, topics: ['ruby', 'rails'])
    create(:repository, host: @host, topics: ['ruby', 'python'])
    create(:repository, host: @host, topics: ['javascript'])

    Topic.sync_for_host(@host)

    assert_equal 4, Topic.where(host: @host).count

    ruby_topic = Topic.find_by(host: @host, name: 'ruby')
    assert_equal 2, ruby_topic.repositories_count

    rails_topic = Topic.find_by(host: @host, name: 'rails')
    assert_equal 1, rails_topic.repositories_count
  end

  test "to_param returns name" do
    topic = Topic.new(name: 'ruby')
    assert_equal 'ruby', topic.to_param
  end
end
