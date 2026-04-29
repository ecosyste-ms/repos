xml.instruct! :xml, version: '1.0', encoding: 'UTF-8'
xml.rss version: '2.0' do
  xml.channel do
    xml.title "#{@host.name} repositories"
    xml.description "Latest repositories indexed for #{@host.name}"
    xml.link host_url(@host)
    xml.language 'en'

    @repositories.each do |repository|
      xml.item do
        xml.title repository.full_name
        xml.link host_repository_url(@host, repository.full_name)
        xml.guid host_repository_url(@host, repository.full_name), isPermaLink: true
        xml.pubDate repository.updated_at.rfc2822 if repository.updated_at.present?
      end
    end
  end
end
