namespace :scorecards do
  desc 'Analyze scorecard data for check coverage and repository statistics'
  task analyze: :environment do
    puts "Analyzing Scorecard Data"
    puts "=" * 60
    puts

    total_scorecards = Scorecard.count
    with_repo = Scorecard.with_repository.count
    without_repo = Scorecard.without_repository.count

    puts "Total scorecards: #{total_scorecards}"
    puts "With linked repository: #{with_repo}"
    puts "Without linked repository: #{without_repo}"
    puts

    # Check coverage analysis
    puts "Check Coverage Analysis"
    puts "-" * 60

    check_stats = Hash.new { |h, k| h[k] = { total: 0, applicable: 0, scores: [] } }
    score_buckets = Hash.new(0)
    processed = 0

    Scorecard.find_each do |scorecard|
      processed += 1
      print "\rProcessing scorecards: #{processed}" if processed % 10_000 == 0

      # Score distribution
      if scorecard.score
        bucket = case scorecard.score
                 when 0...1 then "0-1"
                 when 1...2 then "1-2"
                 when 2...3 then "2-3"
                 when 3...4 then "3-4"
                 when 4...5 then "4-5"
                 when 5...6 then "5-6"
                 when 6...7 then "6-7"
                 when 7...8 then "7-8"
                 when 8...9 then "8-9"
                 when 9..10 then "9-10"
                 else "unknown"
                 end
        score_buckets[bucket] += 1
      end

      next unless scorecard.checks.present?

      scorecard.checks.each do |check|
        name = check['name']
        score = check['score']

        check_stats[name][:total] += 1
        if score >= 0
          check_stats[name][:applicable] += 1
          check_stats[name][:scores] << score
        end
      end
    end
    puts "\rProcessed #{processed} scorecards"

    puts
    puts format("%-25s %8s %8s %8s %8s %8s", "Check Name", "Total", "N/A", "Applic%", "AvgScore", "Risk")
    puts "-" * 75

    sorted_checks = check_stats.sort_by { |name, _| name }
    sorted_checks.each do |name, stats|
      na_count = stats[:total] - stats[:applicable]
      applicable_pct = stats[:total] > 0 ? (stats[:applicable].to_f / stats[:total] * 100).round(1) : 0
      avg_score = stats[:scores].any? ? (stats[:scores].sum.to_f / stats[:scores].size).round(2) : 0
      risk = Scorecard.risk_levels[name] || 'Unknown'

      puts format("%-25s %8d %8d %7.1f%% %8.2f %8s", name, stats[:total], na_count, applicable_pct, avg_score, risk)
    end

    # Score distribution (already collected above)
    puts
    puts "Overall Score Distribution"
    puts "-" * 60

    puts format("%-10s %10s %10s", "Score", "Count", "Percent")
    puts "-" * 35
    %w[0-1 1-2 2-3 3-4 4-5 5-6 6-7 7-8 8-9 9-10].each do |bucket|
      count = score_buckets[bucket]
      pct = total_scorecards > 0 ? (count.to_f / total_scorecards * 100).round(1) : 0
      puts format("%-10s %10d %9.1f%%", bucket, count, pct)
    end

    # Repository popularity analysis (only for linked repos)
    puts
    puts "Repository Popularity Analysis (linked repos only)"
    puts "-" * 60

    star_buckets = Hash.new(0)
    fork_buckets = Hash.new(0)
    total_with_stars = 0
    repo_processed = 0

    Scorecard.with_repository.includes(:repository).find_each do |scorecard|
      repo_processed += 1
      print "\rProcessing repos: #{repo_processed}" if repo_processed % 10_000 == 0

      repo = scorecard.repository
      next unless repo

      stars = repo.stargazers_count || 0
      forks = repo.forks_count || 0
      total_with_stars += 1

      star_bucket = case stars
                    when 0 then "0"
                    when 1..10 then "1-10"
                    when 11..100 then "11-100"
                    when 101..1000 then "101-1K"
                    when 1001..10000 then "1K-10K"
                    when 10001..100000 then "10K-100K"
                    else "100K+"
                    end
      star_buckets[star_bucket] += 1

      fork_bucket = case forks
                    when 0 then "0"
                    when 1..10 then "1-10"
                    when 11..100 then "11-100"
                    when 101..1000 then "101-1K"
                    when 1001..10000 then "1K-10K"
                    else "10K+"
                    end
      fork_buckets[fork_bucket] += 1
    end
    puts "\rProcessed #{repo_processed} repos"

    puts
    puts "Stars Distribution:"
    puts format("%-12s %10s %10s", "Stars", "Count", "Percent")
    puts "-" * 35
    %w[0 1-10 11-100 101-1K 1K-10K 10K-100K 100K+].each do |bucket|
      count = star_buckets[bucket]
      pct = total_with_stars > 0 ? (count.to_f / total_with_stars * 100).round(1) : 0
      puts format("%-12s %10d %9.1f%%", bucket, count, pct)
    end

    puts
    puts "Forks Distribution:"
    puts format("%-12s %10s %10s", "Forks", "Count", "Percent")
    puts "-" * 35
    %w[0 1-10 11-100 101-1K 1K-10K 10K+].each do |bucket|
      count = fork_buckets[bucket]
      pct = total_with_stars > 0 ? (count.to_f / total_with_stars * 100).round(1) : 0
      puts format("%-12s %10d %9.1f%%", bucket, count, pct)
    end

    # Low activity repos
    puts
    puts "Activity Analysis"
    puts "-" * 60

    zero_stars = star_buckets["0"]
    low_stars = star_buckets["0"] + star_buckets["1-10"]
    zero_stars_pct = total_with_stars > 0 ? (zero_stars.to_f / total_with_stars * 100).round(1) : 0
    low_stars_pct = total_with_stars > 0 ? (low_stars.to_f / total_with_stars * 100).round(1) : 0

    puts "Repos with 0 stars: #{zero_stars} (#{zero_stars_pct}%)"
    puts "Repos with <=10 stars: #{low_stars} (#{low_stars_pct}%)"
    puts
    puts "These low-activity repos may represent scanning overhead with limited value."
  end

  desc 'Export scorecard analysis to JSON'
  task analyze_json: :environment do
    results = {
      generated_at: Time.now.iso8601,
      total_scorecards: Scorecard.count,
      with_repository: Scorecard.with_repository.count,
      checks: {},
      score_distribution: Hash.new(0),
      stars_distribution: Hash.new(0),
      forks_distribution: Hash.new(0)
    }

    check_stats = Hash.new { |h, k| h[k] = { total: 0, applicable: 0, not_applicable: 0, scores: [] } }
    processed = 0

    Scorecard.find_each do |scorecard|
      processed += 1
      $stderr.print "\rProcessing scorecards: #{processed}" if processed % 10_000 == 0

      # Score distribution
      if scorecard.score
        bucket = (scorecard.score.floor rescue 0)
        bucket = [bucket, 10].min
        results[:score_distribution][bucket] += 1
      end

      # Check stats
      next unless scorecard.checks.present?
      scorecard.checks.each do |check|
        name = check['name']
        score = check['score']
        check_stats[name][:total] += 1
        if score >= 0
          check_stats[name][:applicable] += 1
          check_stats[name][:scores] << score
        else
          check_stats[name][:not_applicable] += 1
        end
      end
    end
    $stderr.puts "\rProcessed #{processed} scorecards"

    check_stats.each do |name, stats|
      results[:checks][name] = {
        total: stats[:total],
        applicable: stats[:applicable],
        not_applicable: stats[:not_applicable],
        applicable_percent: stats[:total] > 0 ? (stats[:applicable].to_f / stats[:total] * 100).round(2) : 0,
        average_score: stats[:scores].any? ? (stats[:scores].sum.to_f / stats[:scores].size).round(2) : nil,
        score_distribution: stats[:scores].group_by(&:itself).transform_values(&:count),
        risk_level: Scorecard.risk_levels[name]
      }
    end

    # Repository stats
    repo_processed = 0
    Scorecard.with_repository.includes(:repository).find_each do |scorecard|
      repo_processed += 1
      $stderr.print "\rProcessing repos: #{repo_processed}" if repo_processed % 10_000 == 0

      repo = scorecard.repository
      next unless repo

      stars = repo.stargazers_count || 0
      star_bucket = case stars
                    when 0 then "0"
                    when 1..10 then "1-10"
                    when 11..100 then "11-100"
                    when 101..1000 then "101-1000"
                    when 1001..10000 then "1001-10000"
                    when 10001..100000 then "10001-100000"
                    else "100000+"
                    end
      results[:stars_distribution][star_bucket] += 1

      forks = repo.forks_count || 0
      fork_bucket = case forks
                    when 0 then "0"
                    when 1..10 then "1-10"
                    when 11..100 then "11-100"
                    when 101..1000 then "101-1000"
                    when 1001..10000 then "1001-10000"
                    else "10000+"
                    end
      results[:forks_distribution][fork_bucket] += 1
    end
    $stderr.puts "\rProcessed #{repo_processed} repos"

    puts JSON.pretty_generate(results)
  end

  desc 'Show checks sorted by applicability (lowest first - potential waste)'
  task check_applicability: :environment do
    puts "Check Applicability Analysis (sorted by applicability, lowest first)"
    puts "=" * 80
    puts
    puts "Checks with low applicability may represent wasted scanning effort."
    puts

    check_stats = Hash.new { |h, k| h[k] = { total: 0, applicable: 0, scores: [] } }
    processed = 0

    Scorecard.find_each do |scorecard|
      processed += 1
      print "\rProcessing: #{processed}" if processed % 10_000 == 0

      next unless scorecard.checks.present?

      scorecard.checks.each do |check|
        name = check['name']
        score = check['score']

        check_stats[name][:total] += 1
        if score >= 0
          check_stats[name][:applicable] += 1
          check_stats[name][:scores] << score
        end
      end
    end
    puts "\rProcessed #{processed} scorecards"

    puts
    puts format("%-25s %8s %8s %8s %8s %s", "Check Name", "Applic%", "AvgScore", "N/A", "Total", "Risk")
    puts "-" * 85

    sorted = check_stats.sort_by { |_, stats| stats[:total] > 0 ? stats[:applicable].to_f / stats[:total] : 0 }
    sorted.each do |name, stats|
      na_count = stats[:total] - stats[:applicable]
      applicable_pct = stats[:total] > 0 ? (stats[:applicable].to_f / stats[:total] * 100).round(1) : 0
      avg_score = stats[:scores].any? ? (stats[:scores].sum.to_f / stats[:scores].size).round(2) : 0
      risk = Scorecard.risk_levels[name] || 'Unknown'

      puts format("%-25s %7.1f%% %8.2f %8d %8d %s", name, applicable_pct, avg_score, na_count, stats[:total], risk)
    end
  end

  desc 'Analyze potential scanning waste (low-value repos)'
  task waste_analysis: :environment do
    puts "Scanning Waste Analysis"
    puts "=" * 60
    puts

    total = Scorecard.with_repository.count
    puts "Total scorecards with linked repos: #{total}"
    puts

    # Count repos by various criteria
    zero_stars = 0
    low_stars = 0      # <= 10
    very_low = 0       # <= 100
    archived = 0
    no_recent_commits = 0
    forks = 0
    processed = 0

    one_year_ago = 1.year.ago

    Scorecard.with_repository.includes(:repository).find_each do |scorecard|
      processed += 1
      print "\rProcessing: #{processed}" if processed % 10_000 == 0

      repo = scorecard.repository
      next unless repo

      stars = repo.stargazers_count || 0
      zero_stars += 1 if stars == 0
      low_stars += 1 if stars <= 10
      very_low += 1 if stars <= 100

      archived += 1 if repo.archived?
      forks += 1 if repo.fork?
      no_recent_commits += 1 if repo.pushed_at && repo.pushed_at < one_year_ago
    end
    puts "\rProcessed #{processed} repos"

    puts
    puts "Potential low-value scans:"
    puts format("  Zero stars:           %8d (%5.1f%%)", zero_stars, pct(zero_stars, total))
    puts format("  <= 10 stars:          %8d (%5.1f%%)", low_stars, pct(low_stars, total))
    puts format("  <= 100 stars:         %8d (%5.1f%%)", very_low, pct(very_low, total))
    puts format("  Archived repos:       %8d (%5.1f%%)", archived, pct(archived, total))
    puts format("  Forks:                %8d (%5.1f%%)", forks, pct(forks, total))
    puts format("  No commits in 1 year: %8d (%5.1f%%)", no_recent_commits, pct(no_recent_commits, total))
    puts
    puts "Note: Categories overlap. A repo may be counted in multiple categories."
  end
end

def pct(count, total)
  total > 0 ? (count.to_f / total * 100).round(1) : 0
end
