// SPA proof of concept - vanilla JS, no dependencies
// Replaces server-rendered ERB views with client-side API consumers

(function() {
    'use strict';

    // ---------------------------------------------------------------------------
    // Config
    // ---------------------------------------------------------------------------

    var API_BASE = '/api/v1';
    var SPA_BASE = '/spa'; // prefix for all SPA routes (remove when SPA becomes the default)

    // ---------------------------------------------------------------------------
    // API client
    // ---------------------------------------------------------------------------

    var api = {
        get: function(path, params) {
            var url = new URL(API_BASE + path, location.origin);
            if (params) {
                Object.keys(params).forEach(function(k) {
                    if (params[k] != null) url.searchParams.set(k, params[k]);
                });
            }
            return fetch(url).then(function(r) {
                var links = parseLinkHeader(r.headers.get('Link'));
                var total = r.headers.get('Total');
                return r.json().then(function(data) {
                    return { data: data, links: links, total: total };
                });
            });
        },

        hosts: function(params) { return this.get('/hosts', params); },
        host: function(name) { return this.get('/hosts/' + encodeURIComponent(name)); },
        repositories: function(hostName, params) {
            return this.get('/hosts/' + encodeURIComponent(hostName) + '/repositories', params);
        },
        repository: function(hostName, repoName) {
            return this.get('/hosts/' + encodeURIComponent(hostName) + '/repositories/' + repoName);
        },
        owners: function(hostName, params) {
            return this.get('/hosts/' + encodeURIComponent(hostName) + '/owners', params);
        },
        owner: function(hostName, ownerName) {
            return this.get('/hosts/' + encodeURIComponent(hostName) + '/owners/' + encodeURIComponent(ownerName));
        },
        ownerRepositories: function(hostName, ownerId, params) {
            return this.get('/hosts/' + encodeURIComponent(hostName) + '/owners/' + ownerId + '/repositories', params);
        }
    };

    function parseLinkHeader(header) {
        if (!header) return {};
        var links = {};
        header.split(',').forEach(function(part) {
            var match = part.match(/<([^>]+)>;\s*rel="(\w+)"/);
            if (match) links[match[2]] = match[1];
        });
        return links;
    }

    // ---------------------------------------------------------------------------
    // Router
    // ---------------------------------------------------------------------------

    var routes = [
        { pattern: '/',                                          view: homeView },
        { pattern: '/hosts/kinds/:kind',                         view: hostKindView },
        { pattern: '/hosts/:host/owners',                        view: ownersView },
        { pattern: '/hosts/:host/owners/:owner',                 view: ownerView },
        { pattern: '/hosts/:host/repositories/:repo(/*rest)',    view: repoView },
        { pattern: '/hosts/:host',                               view: hostView },
    ];

    function matchRoute(path) {
        for (var i = 0; i < routes.length; i++) {
            var params = matchPattern(routes[i].pattern, path);
            if (params !== null) return { view: routes[i].view, params: params };
        }
        return null;
    }

    function matchPattern(pattern, path) {
        // Convert pattern to regex
        // :param matches a single segment, :param(/*rest) matches the rest
        var parts = pattern.replace(/\(\/\*(\w+)\)/, '(?:/(?<$1>.+))?').replace(/:(\w+)/g, '(?<$1>[^/]+)');
        var re = new RegExp('^' + parts + '$');
        var m = re.exec(path);
        if (!m) return null;
        return m.groups || {};
    }

    function navigate(path) {
        // Strip SPA_BASE prefix
        var routePath = path;
        if (SPA_BASE && path.indexOf(SPA_BASE) === 0) {
            routePath = path.slice(SPA_BASE.length) || '/';
        }

        var match = matchRoute(routePath);
        if (match) {
            var params = new URLSearchParams(location.search);
            match.view(match.params, params);
            window.scrollTo(0, 0);
        } else {
            content().innerHTML = '<div class="container-sm"><h2>Page not found</h2></div>';
        }
    }

    function spaPath(path) {
        return SPA_BASE + path;
    }

    // Intercept link clicks
    document.addEventListener('click', function(e) {
        var link = e.target.closest('a');
        if (!link) return;
        var href = link.getAttribute('href');
        if (!href) return;

        // Only intercept internal SPA links
        if (href.indexOf(SPA_BASE + '/') === 0 || href === SPA_BASE) {
            e.preventDefault();
            history.pushState(null, '', href);
            navigate(href);
        }
    });

    window.addEventListener('popstate', function() {
        navigate(location.pathname);
    });

    // ---------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------

    function content() {
        return document.getElementById('content');
    }

    function num(n) {
        return (n || 0).toLocaleString();
    }

    function esc(str) {
        if (!str) return '';
        var div = document.createElement('div');
        div.textContent = str;
        return div.innerHTML;
    }

    function timeAgo(dateStr) {
        if (!dateStr) return '';
        var seconds = Math.floor((Date.now() - new Date(dateStr).getTime()) / 1000);
        var intervals = [
            [31536000, 'year'], [2592000, 'month'], [86400, 'day'],
            [3600, 'hour'], [60, 'minute'], [1, 'second']
        ];
        for (var i = 0; i < intervals.length; i++) {
            var count = Math.floor(seconds / intervals[i][0]);
            if (count >= 1) return count + ' ' + intervals[i][1] + (count > 1 ? 's' : '') + ' ago';
        }
        return 'just now';
    }

    function breadcrumb(items) {
        return '<nav aria-label="breadcrumb"><ol class="breadcrumb">' +
            items.map(function(item, i) {
                if (item.href && i < items.length - 1) {
                    return '<li class="breadcrumb-item"><a href="' + item.href + '">' + esc(item.text) + '</a></li>';
                }
                return '<li class="breadcrumb-item active" aria-current="page">' + esc(item.text) + '</li>';
            }).join('') +
        '</ol></nav>';
    }

    function statsRow(stats) {
        var cols = Object.keys(stats);
        var colClass = 'col-md-' + Math.floor(12 / cols.length) + ' col-6 mb-3';
        return '<div class="row mb-3">' +
            cols.map(function(label) {
                var s = stats[label];
                return '<div class="' + colClass + '">' +
                    '<div class="card text-center"><div class="card-body">' +
                        '<h4 class="card-title ' + (s.color || 'text-primary') + ' mb-1">' + num(s.value) + '</h4>' +
                        '<p class="card-text small text-muted mb-0">' + esc(label) + '</p>' +
                    '</div></div>' +
                '</div>';
            }).join('') +
        '</div>';
    }

    function pagination(links, total, currentParams) {
        if (!links.next && !links.prev) return '';
        var html = '<nav><ul class="pagination">';
        if (links.prev) {
            html += '<li class="page-item"><a class="page-link" href="' + spaLinkFromApi(links.prev) + '">Prev</a></li>';
        }
        if (links.next) {
            html += '<li class="page-item"><a class="page-link" href="' + spaLinkFromApi(links.next) + '">Next</a></li>';
        }
        html += '</ul></nav>';
        if (total) html += '<small class="text-muted">' + num(total) + ' total</small>';
        return html;
    }

    // Convert an API pagination URL back to a SPA URL with page param
    function spaLinkFromApi(apiUrl) {
        var url = new URL(apiUrl, location.origin);
        var page = url.searchParams.get('page');
        var current = new URL(location.href);
        if (page) {
            current.searchParams.set('page', page);
        }
        return current.pathname + current.search;
    }

    function loading() {
        content().innerHTML = '<div class="container-sm"><p class="text-muted">Loading...</p></div>';
    }

    // ---------------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------------

    function homeView(params, query) {
        loading();

        // Fetch all hosts (the API paginates, so request a large per_page)
        api.hosts({ per_page: 200 }).then(function(res) {
            var hosts = res.data;

            // Compute summary stats from host data
            var totalRepos = hosts.reduce(function(sum, h) { return sum + (h.repositories_count || 0); }, 0);
            var totalOwners = hosts.reduce(function(sum, h) { return sum + (h.owners_count || 0); }, 0);

            var html = '<div class="container-sm">';

            // Stats cards
            html += statsRow({
                'Hosts':        { value: hosts.length, color: 'text-primary' },
                'Repositories': { value: totalRepos, color: 'text-success' },
                'Owners':       { value: totalOwners, color: 'text-warning' }
            });

            // Group by kind
            var byKind = {};
            hosts.forEach(function(h) {
                var kind = h.kind || 'other';
                if (!byKind[kind]) byKind[kind] = [];
                byKind[kind].push(h);
            });

            Object.keys(byKind).forEach(function(kind) {
                var kindHosts = byKind[kind];
                var kindRepos = kindHosts.reduce(function(sum, h) { return sum + (h.repositories_count || 0); }, 0);

                html += '<div class="card mb-3">';
                html += '<div class="card-header">';
                if (kindHosts[0].icon_url) {
                    html += '<img src="' + esc(kindHosts[0].icon_url) + '" class="me-1 pull-left" height="20" width="20" onerror="this.style.display=\'none\'">';
                }
                html += '<a href="' + spaPath('/hosts/kinds/' + encodeURIComponent(kind)) + '" class="text-decoration-none">' + esc(kind) + '</a> ';
                html += '<span class="text-black-50">' + num(kindHosts.length) + ' hosts - ' + num(kindRepos) + ' repositories</span>';
                html += '</div>';

                html += '<ul class="list-group list-group-flush">';
                kindHosts.slice(0, 20).forEach(function(h) {
                    html += '<li class="list-group-item">';
                    if (h.repositories_count > 0) {
                        html += '<a href="' + spaPath('/hosts/' + encodeURIComponent(h.name)) + '">' + esc(h.name.toLowerCase()) + '</a>';
                    } else {
                        html += esc(h.name);
                    }
                    html += ' <span class="text-black-50">' + num(h.repositories_count) + ' repositories</span>';
                    html += '</li>';
                });
                html += '</ul>';

                if (kindHosts.length > 20) {
                    html += '<div class="card-footer">';
                    html += '<a href="' + spaPath('/hosts/kinds/' + encodeURIComponent(kind)) + '">and ' + (kindHosts.length - 20) + ' more</a>';
                    html += '</div>';
                }

                html += '</div>';
            });

            html += '</div>';
            content().innerHTML = html;
            document.title = 'Ecosyste.ms: Repos';
        });
    }

    function hostKindView(params, query) {
        loading();
        api.hosts({ per_page: 200 }).then(function(res) {
            var hosts = res.data.filter(function(h) { return h.kind === params.kind; });
            var html = '<div class="container-sm">';
            html += breadcrumb([
                { text: 'Hosts', href: spaPath('/') },
                { text: params.kind }
            ]);
            html += '<h2>' + esc(params.kind) + '</h2>';
            html += hostCards(hosts);
            html += '</div>';
            content().innerHTML = html;
            document.title = params.kind + ' | Ecosyste.ms: Repos';
        });
    }

    function hostView(params, query) {
        loading();
        var page = query.get('page') || 1;
        var sort = query.get('sort') || 'id';
        var order = query.get('order') || 'desc';

        api.host(params.host).then(function(res) {
            var host = res.data;

            var html = '<div class="container-sm">';
            html += breadcrumb([
                { text: 'Hosts', href: spaPath('/') },
                { text: host.name }
            ]);

            // Host card
            html += '<div class="card mb-3"><div class="card-body">';
            html += '<h1 class="card-title h3 mb-0">';
            html += '<a href="' + esc(host.url) + '" target="_blank">' + esc(host.name) + '</a>';
            html += '</h1></div></div>';

            // Stats
            html += statsRow({
                'Repositories': { value: host.repositories_count, color: 'text-primary' },
                'Owners':       { value: host.owners_count, color: 'text-success' }
            });

            // Status alerts
            if (host.status) {
                var statusColor = host.online ? 'success' : 'danger';
                html += '<div class="alert alert-' + statusColor + ' py-2 px-3 mb-2 small">';
                html += '<strong>Status:</strong> ' + esc(host.status);
                if (host.last_error) html += ' - ' + esc(host.last_error);
                if (host.status_checked_at) {
                    html += ' <span class="text-muted ms-2">checked ' + timeAgo(host.status_checked_at) + '</span>';
                }
                html += '</div>';
            }

            if (host.robots_txt_status) {
                var robotsColor = host.can_crawl_api ? 'success' : 'warning';
                if (host.robots_txt_status === 'not_found') robotsColor = 'info';
                html += '<div class="alert alert-' + robotsColor + ' py-2 px-3 mb-2 small">';
                html += '<strong>Robots.txt:</strong> ';
                if (host.robots_txt_status === 'success') {
                    html += '<a href="' + esc(host.robots_txt_url) + '" target="_blank" class="alert-link">Found</a>';
                    html += host.can_crawl_api ? ' - API crawling <strong>allowed</strong>' : ' - API crawling <strong>blocked</strong>';
                } else if (host.robots_txt_status === 'not_found') {
                    html += 'Not found - all crawling allowed by default';
                } else {
                    html += esc(host.robots_txt_status);
                }
                if (host.robots_txt_updated_at) {
                    html += ' <span class="text-muted ms-2">checked ' + timeAgo(host.robots_txt_updated_at) + '</span>';
                }
                html += '</div>';
            }

            // Tabs
            html += hostTabs(host, 'repositories');

            // Sort dropdown
            html += '<div class="mb-3">';
            html += sortDropdown(params.host, sort, [
                { key: 'pushed_at', label: 'Recently pushed' },
                { key: 'stargazers_count', label: 'Stars' },
                { key: 'forks_count', label: 'Forks' }
            ]);
            html += '</div>';

            html += '<div id="repo-list"><p class="text-muted">Loading repositories...</p></div>';
            html += '</div>';
            content().innerHTML = html;
            document.title = host.name + ' | Ecosyste.ms: Repos';

            // Load repositories
            loadRepoList(params.host, { page: page, sort: sort, order: order });
        });
    }

    function loadRepoList(hostName, params) {
        api.repositories(hostName, params).then(function(res) {
            var el = document.getElementById('repo-list');
            if (!el) return;
            el.innerHTML = repoCards(res.data, hostName) + pagination(res.links, res.total, params);
        });
    }

    function ownersView(params, query) {
        loading();
        var page = query.get('page') || 1;

        api.host(params.host).then(function(hostRes) {
            var host = hostRes.data;

            api.owners(params.host, { page: page, per_page: 30 }).then(function(res) {
                var html = '<div class="container-sm">';
                html += breadcrumb([
                    { text: 'Hosts', href: spaPath('/') },
                    { text: host.name, href: spaPath('/hosts/' + encodeURIComponent(host.name)) },
                    { text: 'Owners' }
                ]);

                html += hostTabs(host, 'owners');

                html += '<div class="row">';
                res.data.forEach(function(owner) {
                    html += '<div class="col-md-6 mb-3">';
                    html += '<div class="card"><div class="card-body">';
                    html += '<h5><a href="' + spaPath('/hosts/' + encodeURIComponent(host.name) + '/owners/' + encodeURIComponent(owner.login)) + '">' + esc(owner.login) + '</a></h5>';
                    html += '<p class="text-muted mb-0">' + num(owner.repositories_count) + ' repositories</p>';
                    html += '</div></div></div>';
                });
                html += '</div>';

                html += pagination(res.links, res.total, { page: page });
                html += '</div>';
                content().innerHTML = html;
                document.title = 'Owners - ' + host.name + ' | Ecosyste.ms: Repos';
            });
        });
    }

    function ownerView(params, query) {
        loading();
        var page = query.get('page') || 1;

        Promise.all([
            api.host(params.host),
            api.owner(params.host, params.owner)
        ]).then(function(results) {
            var host = results[0].data;
            var owner = results[1].data;

            var html = '<div class="container-sm">';
            html += breadcrumb([
                { text: 'Hosts', href: spaPath('/') },
                { text: host.name, href: spaPath('/hosts/' + encodeURIComponent(host.name)) },
                { text: 'Owners', href: spaPath('/hosts/' + encodeURIComponent(host.name) + '/owners') },
                { text: owner.login }
            ]);

            html += '<div class="row"><div class="col-md-8">';
            html += '<h1>' + esc(owner.login) + '</h1>';
            if (owner.description) html += '<p>' + esc(owner.description) + '</p>';
            html += '<div id="owner-repos"><p class="text-muted">Loading repositories...</p></div>';
            html += '</div>';

            html += '<div class="col-md-4">';
            html += '<div class="card"><div class="card-body">';
            html += '<p><strong>Repositories:</strong> ' + num(owner.repositories_count) + '</p>';
            if (owner.name) html += '<p><strong>Name:</strong> ' + esc(owner.name) + '</p>';
            if (owner.website) html += '<p><a href="' + esc(owner.website) + '" target="_blank">Website</a></p>';
            html += '</div></div>';
            html += '</div></div>';
            html += '</div>';
            content().innerHTML = html;
            document.title = owner.login + ' | Ecosyste.ms: Repos';

            // Load repos
            api.ownerRepositories(params.host, owner.id, { page: page }).then(function(res) {
                var el = document.getElementById('owner-repos');
                if (!el) return;
                el.innerHTML = repoCards(res.data, host.name) + pagination(res.links, res.total, { page: page });
            });
        });
    }

    function repoView(params, query) {
        loading();
        var repoName = params.repo;
        if (params.rest) repoName += '/' + params.rest;

        api.repository(params.host, repoName).then(function(res) {
            var repo = res.data;

            var html = '<div class="container-sm">';
            html += breadcrumb([
                { text: 'Hosts', href: spaPath('/') },
                { text: params.host, href: spaPath('/hosts/' + encodeURIComponent(params.host)) },
                { text: repo.full_name }
            ]);

            html += '<div class="row"><div class="col-md-8">';

            // Header
            html += '<h1 class="h3">';
            html += '<a href="' + esc(repo.html_url || repo.url) + '" target="_blank">' + esc(repo.full_name) + '</a>';
            html += '</h1>';
            if (repo.description) html += '<p>' + esc(repo.description) + '</p>';
            if (repo.topics && repo.topics.length) {
                html += '<p>' + repo.topics.map(function(t) {
                    return '<span class="badge bg-secondary me-1">' + esc(t) + '</span>';
                }).join('') + '</p>';
            }

            // File browser placeholder
            if (repo.download_url) {
                html += '<div class="card mb-3"><div class="card-header"><strong id="files-header"></strong></div>';
                html += '<ul class="list-group list-group-flush" id="files-list"></ul>';
                html += '<div class="card-body" id="files-content" style="display:none"></div>';
                html += '</div>';
            }

            // Readme placeholder
            html += '<div class="card mb-3" id="readme" style="display:none">';
            html += '<div class="card-header"><strong id="readme-header"></strong></div>';
            html += '<div class="card-body" id="readme-content"></div>';
            html += '</div>';

            html += '</div>';

            // Sidebar
            html += '<div class="col-md-4">';
            html += '<div class="card mb-3"><div class="card-body">';
            var sidebarItems = [
                ['Stars', repo.stargazers_count],
                ['Forks', repo.forks_count],
                ['Open issues', repo.open_issues_count],
                ['License', repo.license],
                ['Language', repo.language],
                ['Size', repo.size ? Math.round(repo.size / 1024) + ' MB' : null],
                ['Created', repo.created_at ? new Date(repo.created_at).toLocaleDateString() : null],
                ['Updated', repo.updated_at ? timeAgo(repo.updated_at) : null],
                ['Pushed', repo.pushed_at ? timeAgo(repo.pushed_at) : null]
            ];
            sidebarItems.forEach(function(item) {
                if (item[1] != null) {
                    html += '<div class="mb-1"><strong>' + item[0] + ':</strong> ' + esc(String(item[1])) + '</div>';
                }
            });
            html += '</div></div>';
            html += '</div>';

            html += '</div></div>';
            content().innerHTML = html;
            document.title = repo.full_name + ' | Ecosyste.ms: Repos';

            // Load file browser
            if (repo.download_url) {
                loadFileBrowser(repo.download_url, repo.full_name.split('/').pop(), query.get('path') || '');
            }

            // Load readme
            if (repo.download_url) {
                loadReadme(repo.download_url);
            }
        });
    }

    // ---------------------------------------------------------------------------
    // File browser (ported from existing application.js)
    // ---------------------------------------------------------------------------

    function loadFileBrowser(downloadUrl, basename, path) {
        var archivesService = 'https://archives.ecosyste.ms';
        var headerEl = document.getElementById('files-header');

        // Render breadcrumb header
        var headerHtml = '<a href="' + location.pathname + '">' + esc(basename) + '</a>';
        if (path) {
            var parts = path.split('/');
            parts.forEach(function(part, i) {
                headerHtml += ' / ';
                if (i < parts.length - 1) {
                    var subpath = parts.slice(0, i + 1).join('/');
                    headerHtml += '<a href="' + location.pathname + '?path=' + encodeURIComponent(subpath) + '">' + esc(part) + '</a>';
                } else {
                    headerHtml += esc(part);
                }
            });
        }
        if (headerEl) headerEl.innerHTML = headerHtml;

        var url;
        if (path && path.length > 0) {
            url = archivesService + '/api/v1/archives/contents?url=' + encodeURIComponent(downloadUrl) + '&path=' + encodeURIComponent(path);
        } else {
            url = archivesService + '/api/v1/archives/list?url=' + encodeURIComponent(downloadUrl);
        }

        fetch(url).then(function(r) { return r.json(); }).then(function(data) {
            if (path && path.length > 0) {
                if (data.directory) {
                    renderFileList(data.contents, path);
                } else {
                    renderFileContents(data);
                }
            } else {
                renderFileList(data, path);
            }
        }).catch(function() {
            var el = document.getElementById('files-content');
            if (el) { el.textContent = 'Error loading files'; el.style.display = ''; }
        });
    }

    function renderFileList(files, path) {
        var listEl = document.getElementById('files-list');
        if (!listEl) return;
        var html = '';

        if (path && path.length > 0) {
            var parts = path.split('/');
            var parent = parts.slice(0, parts.length - 1).join('/');
            html += '<li class="list-group-item"><a href="' + location.pathname + '?path=' + encodeURIComponent(parent) + '">..</a></li>';
        }

        files.forEach(function(f) {
            if (f.split('/').length === 1) {
                var fullPath = (path && path.length > 0) ? path + '/' + f : f;
                html += '<li class="list-group-item"><a href="' + location.pathname + '?path=' + encodeURIComponent(fullPath) + '">' + esc(f) + '</a></li>';
            }
        });

        listEl.innerHTML = html;
    }

    function renderFileContents(data) {
        var el = document.getElementById('files-content');
        if (!el) return;
        el.style.display = '';
        el.innerHTML = '<pre><code>' + esc(data.contents) + '</code></pre>';
        if (typeof hljs !== 'undefined') hljs.highlightAll();
    }

    function loadReadme(downloadUrl) {
        var archivesService = 'https://archives.ecosyste.ms';
        var url = archivesService + '/api/v1/archives/readme?url=' + encodeURIComponent(downloadUrl);

        fetch(url).then(function(r) { return r.json(); }).then(function(data) {
            var container = document.getElementById('readme');
            var header = document.getElementById('readme-header');
            var body = document.getElementById('readme-content');
            if (!container || !header || !body) return;

            header.textContent = data.name || 'README';
            body.innerHTML = data.html || '';
            container.style.display = '';
        }).catch(function() {
            // Silently fail - not all repos have readmes
        });
    }

    // ---------------------------------------------------------------------------
    // Shared components
    // ---------------------------------------------------------------------------

    function hostTabs(host, active) {
        return '<ul class="nav nav-tabs my-3">' +
            '<li class="nav-item">' +
                '<a class="nav-link ' + (active === 'repositories' ? 'active' : '') + '" href="' + spaPath('/hosts/' + encodeURIComponent(host.name)) + '">' +
                    'Repositories <span class="badge bg-secondary rounded-pill">' + num(host.repositories_count) + '</span>' +
                '</a>' +
            '</li>' +
            '<li class="nav-item">' +
                '<a class="nav-link ' + (active === 'owners' ? 'active' : '') + '" href="' + spaPath('/hosts/' + encodeURIComponent(host.name) + '/owners') + '">' +
                    'Owners <span class="badge bg-secondary rounded-pill">' + num(host.owners_count) + '</span>' +
                '</a>' +
            '</li>' +
        '</ul>';
    }

    function sortDropdown(hostName, currentSort, options) {
        var html = '<div class="dropdown d-inline-block">';
        html += '<button class="btn btn-light dropdown-toggle" type="button" data-bs-toggle="dropdown">Sort</button>';
        html += '<ul class="dropdown-menu">';
        options.forEach(function(opt) {
            var active = currentSort === opt.key ? ' active' : '';
            var href = spaPath('/hosts/' + encodeURIComponent(hostName)) + '?sort=' + opt.key + '&order=desc';
            html += '<li><a class="dropdown-item' + active + '" href="' + href + '">' + esc(opt.label) + '</a></li>';
        });
        html += '</ul></div>';
        return html;
    }

    function hostCards(hosts) {
        return hosts.map(function(host) {
            var html = '<div class="card mb-3"><div class="card-body pb-1"><div class="d-flex">';
            html += '<div class="flex-grow-1 ms-3 text-break">';
            html += '<h5 class="card-title">';
            if (host.repositories_count > 0) {
                html += '<a href="' + spaPath('/hosts/' + encodeURIComponent(host.name)) + '">' + esc(host.name) + '</a>';
            } else {
                html += esc(host.name);
            }
            html += '</h5>';
            html += '<p class="card-subtitle mb-2 text-muted">';
            if (host.repositories_count > 0) {
                html += num(host.repositories_count) + ' repositories<br/>';
                html += num(host.owners_count) + ' owners';
            } else {
                html += '<i>Coming soon</i>';
            }
            html += '</p></div>';
            if (host.icon_url) {
                html += '<div class="flex-shrink-0"><img src="' + esc(host.icon_url) + '" class="rounded" height="40" width="40" onerror="this.style.display=\'none\'"></div>';
            }
            html += '</div></div></div>';
            return html;
        }).join('');
    }

    function repoCards(repos, hostName) {
        return repos.map(function(r) {
            var repoPath = spaPath('/hosts/' + encodeURIComponent(hostName) + '/repositories/' + r.full_name);
            var html = '<div class="card mb-3"><div class="card-body pb-1"><div class="d-flex">';
            html += '<div class="flex-grow-1 ms-3 text-break">';
            html += '<h5 class="card-title"><a href="' + repoPath + '">' + esc(r.full_name) + '</a></h5>';
            html += '<p class="card-subtitle mb-2 text-muted">';
            if (r.description) html += esc(r.description) + '<br/>';
            var meta = [];
            if (r.language) meta.push(r.language);
            if (r.stargazers_count) meta.push(num(r.stargazers_count) + ' stars');
            if (r.forks_count) meta.push(num(r.forks_count) + ' forks');
            if (r.pushed_at) meta.push('pushed ' + timeAgo(r.pushed_at));
            html += meta.join(' - ');
            html += '</p></div>';
            html += '</div></div></div>';
            return html;
        }).join('');
    }

    // ---------------------------------------------------------------------------
    // Boot
    // ---------------------------------------------------------------------------

    navigate(location.pathname);

})();
