
# Initialize counters
archived_count = 0
fork_count = 0
not_archived_count = 0
not_fork_count = 0
total_log_stars = 0
processed_count = 0

puts "Analyzing repositories with scorecards..."
puts "-" * 50

Scorecard.includes(:repository).find_each(batch_size: 10) do |scorecard|
  repo = scorecard.repository
  next unless repo

    processed_count += 1
    
    # Count archived repositories
    if repo.archived?
      archived_count += 1
    else
      not_archived_count += 1
    end
    
    # Count fork repositories  
    if repo.fork?
      fork_count += 1
    else
      not_fork_count += 1
    end
    
    # Collect star counts (log10)
    stars = repo.stargazers_count || 0
    log_stars = stars > 0 ? Math.log10(stars) : 0
    total_log_stars += log_stars
    
    # Progress indicator every 10000 repos
    if processed_count % 10000 == 0
      puts "  Processed #{processed_count} repos..."
    end

end

puts "=" * 50
puts "SUMMARY:"
puts "=" * 50
puts "Total repositories processed: #{processed_count}"
puts "Archived: #{archived_count}"
puts "Not archived: #{not_archived_count}"
puts "Forks: #{fork_count}"
puts "Not forks: #{not_fork_count}"
puts ""
puts "Star statistics (log10):"
puts "  Mean: #{processed_count > 0 ? (total_log_stars / processed_count).round(2) : 0}"
puts "  Total log10 stars: #{total_log_stars.round(2)}"