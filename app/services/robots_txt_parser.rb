class RobotsTxtParser
  def initialize(robots_txt_content)
    @robots_txt_content = robots_txt_content
  end

  def can_crawl?(path, user_agent = nil)
    user_agent ||= ENV.fetch('USER_AGENT', 'repos.ecosyste.ms')
    return true if @robots_txt_content.blank?
    
    path = path.to_s.start_with?('/') ? path : "/#{path}"
    
    rules = parse_robots_txt
    user_agent_rules = rules[user_agent.downcase] || rules['*'] || {}
    
    disallowed_paths = user_agent_rules[:disallow] || []
    allowed_paths = user_agent_rules[:allow] || []
    
    disallowed_paths.each do |disallow_pattern|
      next if disallow_pattern.blank?
      if path_matches_pattern?(path, disallow_pattern)
        allowed_paths.each do |allow_pattern|
          next if allow_pattern.blank?
          return true if path_matches_pattern?(path, allow_pattern)
        end
        return false
      end
    end
    
    true
  end

  private

  def parse_robots_txt
    return {} if @robots_txt_content.blank?
    
    rules = {}
    current_user_agents = []
    
    @robots_txt_content.lines.each do |line|
      line = line.strip.downcase
      next if line.empty? || line.start_with?('#')
      
      if line.start_with?('user-agent:')
        user_agent = line.sub('user-agent:', '').strip
        current_user_agents = [user_agent]
      elsif line.start_with?('disallow:')
        path = line.sub('disallow:', '').strip
        current_user_agents.each do |ua|
          rules[ua] ||= { disallow: [], allow: [] }
          rules[ua][:disallow] << path
        end
      elsif line.start_with?('allow:')
        path = line.sub('allow:', '').strip  
        current_user_agents.each do |ua|
          rules[ua] ||= { disallow: [], allow: [] }
          rules[ua][:allow] << path
        end
      end
    end
    
    rules
  end

  def path_matches_pattern?(path, pattern)
    return false if pattern.blank?
    return true if pattern == '/'
    
    if pattern.include?('*')
      regex_pattern = Regexp.escape(pattern).gsub('\*', '.*')
      path.match?(/^#{regex_pattern}/)
    else
      path.start_with?(pattern)
    end
  end
end