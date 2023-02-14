SitemapGenerator::Sitemap.default_host = "https://repos.ecosyste.ms"
SitemapGenerator::Sitemap.sitemaps_path = 'sitemap/'
SitemapGenerator::Sitemap.create do
  add root_path, priority: 1, changefreq: 'daily'

  Host.all.each do |host|
    add host_path(host), priority: 0.9, changefreq: 'daily'
    add host_owners_path(host), priority: 0.9, changefreq: 'daily'
    host.repositories.order('updated_at DESC').limit(1000).each do |repository|
      add host_repository_path(host,repository), priority: 0.8, changefreq: 'daily'
    end

    host.owners.order('updated_at DESC').limit(1000).each do |owner|
      add host_owner_path(host, owner), priority: 0.8, changefreq: 'daily'
    end
  end
end