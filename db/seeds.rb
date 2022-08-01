default_hosts = [
  {name: 'GitHub', url: 'https://github.com', kind: 'github'},
  {name: 'GitLab.com', url: 'https://gitlab.com', kind: 'gitlab'},
  {name: 'Bitbucket.org', url: 'https://bitbucket.org', kind: 'bitbucket'},
  {name: 'SourceHut', url: 'https://sr.ht', kind: 'sourcehut'},
  {name: 'Gitea.com', url: 'https://gitea.com', kind: 'gitea'},
  {name: "Codeberg.org", url: "https://codeberg.org", kind: "gitea", org: 'Codeberg-org'}
]

default_hosts.each do |host|
  h = Host.find_or_initialize_by(url: host[:url])
  h.assign_attributes(host)
  h.save
end