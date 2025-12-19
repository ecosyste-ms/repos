namespace :sta do
  REPOS = {
    'github' => %w[
      pyca/cryptography
      pyca/ed25519
      pyca/pynacl
      pyca/pyopenssl
      pyca/infra
      pyca/service-identity
      pypi/warehouse
      sigstore/sigstore-python
      python/cpython
      rubygems/bundler-site
      rubygems/gemstash
      rubygems/rubygems.org
      rubygems/shipit
      rubygems/rubygems
      rubygems/rubygems.github.io
      rubygems/gems
      rubygems/rubygems-generate_index
      rubygems/compact_index
      rubygems/configure-rubygems-credentials
      rubygems/rubygems-mirror
      rubygems/bundler-compose
      rubygems/configure_trusted_publisher
      rubygems/rubygems.org-db-backups
      rubygems/pg-major-update
      rubygems/release-gem
      rubygems/guides
      rubygems/gem_server_conformance
      rubygems/inspector
      rubygems/rfcs
      rubygems/ruby-ssl-check
      rubygems/sigstore-verification
      rubygems/bundler-slackin
      rubygems/gemx
      rubygems/rubygems-server
      rubygems/bundler.github.io
      rubygems/gemwhisperer
      rubygems/bundler-graph
      rubygems/docs
      rubygems/adoption-center
      rubygems/heroku-buildpack-bundler2
      rubygems/bundler
      rubygems/issue-triage
      rubygems/rubygems-chef
      rubygems/rubygems.org-vendor
      rubygems/bors-ng
      rubygems/bundler-changelog
      rubygems/bundlerbot-homu
      rubygems/rubygems-status
      rubygems/cacache-rb
      rubygems/bundlerbot
      rubygems/compact_index_client
      rubygems/bundler-api
      rubygems/rubygems-lita
      rubygems/homu
      rubygems/rubygems-verification
      rubygems/dmca
      rubygems/bundler-source-mercurial
      rubygems/postit
      rubygems/bundler-api-replay
      rubygems/bundler-features
      rubygems/highfive
      rubygems/install
      rubygems/contribute
      rubygems/search
      rubygems/bundler-gem
      rubygems/stat-update
      rubygems/meg
      rubygems/rubygems.org-backup
      rubygems/new-index
      rubygems/rubygems-aws
      rubygems/bundler-api-pollee
      rubygems/apt-tools
      rubygems/gemcutter
      rubygems/bundler-tools
      rubygems/rubygems.org-configs
      rubygems/rails-bundler-test
      rubygems/gem-testers
      rubygems/rubygems-test
      curl/curl
      curl/curl-www
      curl/wcurl
      curl/curl-for-win
      curl/curl-fuzzer
      curl/stats
      curl/curl-container
      curl/quiz
      curl/trurl
      curl/user-survey
      curl/everything-curl
      curl/httpget
      curl/urlget
      curl/curl.dev
      curl/curl-for-qnx
      curl/.github
      curl/doh
      curl/curl-docker
      curl/relative
      curl/curl-up
      curl/fcurl
      curl/curl-cheat-sheet
      curl/h2c
      curl/build-images
      fortran-lang/webpage
      fortran-lang/vscode-fortran-support
      fortran-lang/setup-fortran
      fortran-lang/stdlib-docs
      fortran-lang/stdlib
      fortran-lang/fpm
      fortran-lang/fpm-docs
      fortran-lang/fpm-on-wheels
      fortran-lang/fprettify
      fortran-lang/fortls
      fortran-lang/setup-fpm
      fortran-lang/fftpack
      fortran-lang/homebrew-fortran
      fortran-lang/test-drive
      fortran-lang/minpack
      fortran-lang/registry
      fortran-lang/talks
      fortran-lang/benchmarks
      fortran-lang/playground
      fortran-lang/contributor-graph
      fortran-lang/fortran-forum-article-template
      fortran-lang/http-client
      fortran-lang/fpm-registry
      fortran-lang/fortran-lang.org
      fortran-lang/.github
      fortran-lang/assets
      fortran-lang/fpm-metadata
      fortran-lang/stdlib-cmake-example
      fortran-lang/fpm-haskell
    ],
    'gitlab' => %w[
      m2crypto/m2crypto
    ]
  }.freeze

  desc 'Export releases for STA repos as ndjson'
  task releases: :environment do
    REPOS.each do |host_name, repos|
      host = Host.find_by_name(host_name)
      unless host
        warn "Host not found: #{host_name}"
        next
      end

      repos.each do |full_name|
        begin
          repository = host.find_repository(full_name)
          unless repository
            warn "Syncing repository: #{host_name}/#{full_name}"
            host.sync_repository(full_name)
            repository = host.find_repository(full_name)
            unless repository
              warn "Repository not found after sync: #{host_name}/#{full_name}"
              next
            end
          end

          warn "Syncing releases for #{host_name}/#{full_name}"
          repository.download_releases

          repository.releases.find_each do |release|
            puts Oj.dump({
              host: host_name,
              repository: full_name,
              name: release.name,
              uuid: release.uuid,
              tag_name: release.tag_name,
              target_commitish: release.target_commitish,
              body: release.body,
              draft: release.draft,
              prerelease: release.prerelease,
              published_at: release.published_at&.iso8601,
              created_at: release.created_at&.iso8601,
              author: release.author,
              assets: release.assets,
              last_synced_at: release.last_synced_at&.iso8601,
              html_url: release.html_url
            }, mode: :compat)
          end
        rescue => e
          warn "Error processing #{host_name}/#{full_name}: #{e.message}"
        end
      end
    end
  end
end
