default_hosts = [
  {name: 'GitHub', url: 'https://github.com', kind: 'github'},
  {name: 'GitLab.com', url: 'https://gitlab.com', kind: 'gitlab'},
  {name: 'Bitbucket.org', url: 'https://bitbucket.org', kind: 'bitbucket'},
  {name: 'SourceHut', url: 'https://sr.ht', kind: 'sourcehut'},
  {name: 'Gitea.com', url: 'https://gitea.com', kind: 'gitea'},
  {name: "Codeberg.org", url: "https://codeberg.org", kind: "gitea", org: 'Codeberg-org'},
  {name: "git.fsfe.org", url: "https://git.fsfe.org", kind: "gitea", org: 'fsfe'},
  {name: "opendev.org", url: "https://opendev.org", kind: "gitea", org: 'openstack-infra'},
  {name: "code-repo.d4science.org", url: "https://code-repo.d4science.org", kind: "gitea", org: 'd4science'},
  {name: "salsa.debian.org", url: "https://salsa.debian.org", kind: "gitlab", org: 'debian'},
  {name: "gitlab.haskell.org", url: "https://gitlab.haskell.org", kind: "gitlab", org: 'haskell'},
  {name: "framagit.org", url: "https://framagit.org", kind: "gitlab", org: 'framasoft'},
  {name: "gitlab.gentoo.org", url: "https://gitlab.gentoo.org", kind: "gitlab", org: 'gentoo'},
  {name: "gitlab.freedesktop.org", url: "https://gitlab.freedesktop.org", kind: "gitlab", org: 'freedesktop'},
]

default_hosts.each do |host|
  h = Host.find_or_initialize_by(url: host[:url])
  h.assign_attributes(host)
  h.save
end