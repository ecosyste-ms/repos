namespace :takedown do
  desc "Hide a user and remove their repositories. LOGIN=username [HOST=GitHub]"
  task hide_user: :environment do
    login = ENV['LOGIN']
    host_name = ENV['HOST'] || 'GitHub'
    abort "LOGIN is required" if login.blank?

    ActiveRecord::Base.connection.execute("SET statement_timeout = 0")

    host = Host.find_by('lower(name) = ?', host_name.downcase)
    abort "Host #{host_name} not found" if host.nil?

    owner = host.owners.find_by('lower(login) = ?', login.downcase)
    owner ||= host.owners.create!(login: login)
    owner.update!(hidden: true)
    puts "[repos] hidden owner #{host.name}/#{owner.login}"

    repos = host.repositories.where(owner: [owner.login, login].uniq)
    count = repos.count
    repos.find_each do |repo|
      puts "[repos] destroying #{repo.full_name}"
      repo.destroy
    end
    puts "[repos] destroyed #{count} repositories for #{host.name}/#{login}"
  end

  desc "Report what exists for a user. LOGIN=username [HOST=GitHub]"
  task report: :environment do
    login = ENV['LOGIN']
    host_name = ENV['HOST'] || 'GitHub'
    abort "LOGIN is required" if login.blank?

    ActiveRecord::Base.connection.execute("SET statement_timeout = 0")

    host = Host.find_by('lower(name) = ?', host_name.downcase)
    abort "Host #{host_name} not found" if host.nil?

    owner = host.owners.find_by('lower(login) = ?', login.downcase)
    logins = [login, owner&.login].compact.uniq
    repo_count = host.repositories.where(owner: logins).count
    puts "[repos] #{host.name}/#{login}: owner=#{owner ? (owner.hidden? ? 'hidden' : 'visible') : 'none'} repositories=#{repo_count}"
  end
end
