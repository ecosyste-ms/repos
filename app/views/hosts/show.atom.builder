xml.instruct! :xml, version: '1.0', encoding: 'UTF-8'
xml.feed xmlns: 'http://www.w3.org/2005/Atom' do
  xml.title "#{@host.name} repositories"
  xml.subtitle "Latest repositories indexed for #{@host.name}"
  xml.id host_url(@host)
  xml.link href: host_url(@host)
  xml.link href: host_url(@host, format: :atom), rel: 'self', type: 'application/atom+xml'
  xml.updated((@repositories.first&.updated_at || Time.current).iso8601)

  @repositories.each do |repository|
    xml.entry do
      xml.title repository.full_name
      xml.id host_repository_url(@host, repository.full_name)
      xml.link href: host_repository_url(@host, repository.full_name)
      xml.updated((repository.updated_at || Time.current).iso8601)
    end
  end
end
