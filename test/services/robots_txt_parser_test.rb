require "test_helper"

class RobotsTxtParserTest < ActiveSupport::TestCase
  should 'return true for can_crawl? when no robots.txt content' do
    parser = RobotsTxtParser.new(nil)
    assert parser.can_crawl?('/any/path')
    
    parser = RobotsTxtParser.new('')
    assert parser.can_crawl?('/any/path')
  end

  should 'respect disallow rules in can_crawl?' do
    robots_content = <<~ROBOTS
      User-agent: *
      Disallow: /private/
      Disallow: /admin
    ROBOTS
    
    parser = RobotsTxtParser.new(robots_content)
    
    assert_not parser.can_crawl?('/private/file.txt')
    assert_not parser.can_crawl?('/admin')
    assert parser.can_crawl?('/public/file.txt')
  end

  should 'respect allow rules that override disallow in can_crawl?' do
    robots_content = <<~ROBOTS
      User-agent: *
      Disallow: /private/
      Allow: /private/allowed/
    ROBOTS
    
    parser = RobotsTxtParser.new(robots_content)
    
    assert_not parser.can_crawl?('/private/secret.txt')
    assert parser.can_crawl?('/private/allowed/file.txt')
  end

  should 'handle wildcard patterns in can_crawl?' do
    robots_content = <<~ROBOTS
      User-agent: *
      Disallow: /*.pdf
      Disallow: /temp*
    ROBOTS
    
    parser = RobotsTxtParser.new(robots_content)
    
    assert_not parser.can_crawl?('/document.pdf')
    assert_not parser.can_crawl?('/temp/file.txt')
    assert_not parser.can_crawl?('/temporary')
    assert parser.can_crawl?('/document.txt')
  end

  should 'handle user-agent specific rules in can_crawl?' do
    robots_content = <<~ROBOTS
      User-agent: badbot
      Disallow: /

      User-agent: *
      Disallow: /admin/
    ROBOTS
    
    parser = RobotsTxtParser.new(robots_content)
    
    assert_not parser.can_crawl?('/anything', 'badbot')
    assert_not parser.can_crawl?('/admin/panel', '*')
    assert parser.can_crawl?('/public/file', '*')
  end

  should 'handle paths without leading slash in can_crawl?' do
    robots_content = <<~ROBOTS
      User-agent: *
      Disallow: /private/
    ROBOTS
    
    parser = RobotsTxtParser.new(robots_content)
    
    assert_not parser.can_crawl?('private/file.txt')
    assert parser.can_crawl?('public/file.txt')
  end

  should 'ignore comments and empty lines in can_crawl?' do
    robots_content = <<~ROBOTS
      # This is a comment
      User-agent: *
      
      # Another comment
      Disallow: /private/
      
    ROBOTS
    
    parser = RobotsTxtParser.new(robots_content)
    
    assert_not parser.can_crawl?('/private/file.txt')
    assert parser.can_crawl?('/public/file.txt')
  end

  should 'handle case insensitive user agents in can_crawl?' do
    robots_content = <<~ROBOTS
      User-agent: GoogleBot
      Disallow: /private/
    ROBOTS
    
    parser = RobotsTxtParser.new(robots_content)
    
    assert_not parser.can_crawl?('/private/file.txt', 'googlebot')
    assert_not parser.can_crawl?('/private/file.txt', 'GOOGLEBOT')
    assert parser.can_crawl?('/public/file.txt', 'googlebot')
  end
end