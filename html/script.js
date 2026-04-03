(function() {
    const container = document.getElementById('container');
    const frame = document.getElementById('fiveroster-frame');
    const loading = document.getElementById('loading');
    const closeBtn = document.getElementById('close-btn');

    let isOpen = false;
    let loadTimeout = null;
    let expectedUrl = null;
    const baseUrl = 'https://fiveroster.com';

    var navigationScript = '<script>' +
        // ESC key handler
        'document.addEventListener("keydown", function(e) {' +
        '  if (e.key === "Escape" || e.keyCode === 27) {' +
        '    e.preventDefault();' +
        '    window.parent.postMessage({type: "fiveroster", action: "close"}, "*");' +
        '  }' +
        '});' +
        // Intercept link clicks
        'document.addEventListener("click", function(e) {' +
        '  var target = e.target.closest("a");' +
        '  if (target && target.href && !target.href.startsWith("javascript:")) {' +
        '    e.preventDefault();' +
        '    window.parent.postMessage({type: "fiveroster", action: "navigate", url: target.href}, "*");' +
        '  }' +
        '});' +
        // Intercept form submissions
        'document.addEventListener("submit", function(e) {' +
        '  var form = e.target;' +
        '  e.preventDefault();' +
        '  var formData = new FormData(form);' +
        '  var action = form.action || window.location.href;' +
        '  var method = (form.method || "GET").toUpperCase();' +
        '  window.parent.postMessage({' +
        '    type: "fiveroster",' +
        '    action: "formSubmit",' +
        '    url: action,' +
        '    method: method,' +
        '    data: Object.fromEntries(formData)' +
        '  }, "*");' +
        '});' +
        '<\/script>';

    // Resolve a script src URL to an absolute URL
    function resolveScriptUrl(src) {
        if (src.startsWith('http://') || src.startsWith('https://')) {
            return src;
        }
        if (src.startsWith('//')) {
            return 'https:' + src;
        }
        if (src.startsWith('/')) {
            return baseUrl + src;
        }
        return baseUrl + '/' + src;
    }

    // Fetch external scripts and inline them so they work in srcdoc
    function inlineExternalScripts(html) {
        var scriptRegex = /<script\s+([^>]*?)src\s*=\s*["']([^"']+)["']([^>]*?)>\s*<\/script>/gi;
        var matches = [];
        var match;

        while ((match = scriptRegex.exec(html)) !== null) {
            matches.push({
                fullMatch: match[0],
                attrs: (match[1] + ' ' + match[3]).trim(),
                src: match[2]
            });
        }

        if (matches.length === 0) {
            return Promise.resolve(html);
        }

        var fetches = matches.map(function(m) {
            var scriptUrl = resolveScriptUrl(m.src);
            return fetch(scriptUrl)
                .then(function(r) {
                    if (!r.ok) throw new Error('HTTP ' + r.status);
                    return r.text();
                })
                .then(function(text) {
                    // Escape </script> in fetched content so it doesn't break the inline tag
                    text = text.replace(/<\/script>/gi, '<\\/script>');
                    return { match: m, content: text };
                })
                .catch(function(err) {
                    console.warn('FiveRoster: Failed to fetch script ' + m.src, err);
                    return { match: m, content: '/* Failed to load: ' + m.src + ' */' };
                });
        });

        return Promise.all(fetches).then(function(results) {
            results.forEach(function(r) {
                // Preserve non-src attributes (e.g. type, defer) but remove src-related ones
                var attrs = r.match.attrs
                    .replace(/\s*(async|defer)\s*/gi, ' ')
                    .trim();
                var tag = attrs ? '<script ' + attrs + '>' : '<script>';
                html = html.replace(r.match.fullMatch, tag + r.content + '<\/script>');
            });
            return html;
        });
    }

    // Inject base tag and navigation scripts into HTML
    function prepareHtml(html) {
        // Inject base tag for relative URLs
        if (html.indexOf('<head>') !== -1) {
            html = html.replace('<head>', '<head><base href="' + baseUrl + '/">');
        } else if (html.indexOf('<HEAD>') !== -1) {
            html = html.replace('<HEAD>', '<HEAD><base href="' + baseUrl + '/">');
        }

        // Inject navigation interceptor and ESC handler
        if (html.indexOf('</body>') !== -1) {
            html = html.replace('</body>', navigationScript + '</body>');
        } else if (html.indexOf('</BODY>') !== -1) {
            html = html.replace('</BODY>', navigationScript + '</BODY>');
        } else {
            html = html + navigationScript;
        }

        return html;
    }

    // Fetch URL and inject into iframe via srcdoc
    function loadUrlIntoFrame(url) {
        fetch(url, {
            credentials: 'include'
        })
            .then(function(response) {
                if (!response.ok) {
                    throw new Error('HTTP ' + response.status);
                }
                return response.text();
            })
            .then(function(html) {
                html = prepareHtml(html);
                return inlineExternalScripts(html);
            })
            .then(function(html) {
                frame.srcdoc = html;
            })
            .catch(function(err) {
                console.error('FiveRoster: Failed to load page', err);
                fetch('https://fiveroster-fivem/error', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({})
                }).catch(function() {});
            });
    }

    // Close the NUI
    function closeFrame() {
        isOpen = false;
        expectedUrl = null;

        if (loadTimeout) {
            clearTimeout(loadTimeout);
            loadTimeout = null;
        }

        container.classList.add('hidden');
        frame.srcdoc = '';
        frame.src = 'about:blank';
        frame.classList.remove('loaded');
        loading.classList.remove('hidden');
    }

    // Request close from client
    function requestClose() {
        closeFrame();

        fetch('https://fiveroster-fivem/closeEsc', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        }).catch(function() {});

        fetch('https://fiveroster-fivem/close', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        }).catch(function() {});
    }

    // Close button handler
    if (closeBtn) {
        closeBtn.addEventListener('click', function(e) {
            e.preventDefault();
            e.stopPropagation();
            requestClose();
        });
    }

    // Handle NUI messages from client
    window.addEventListener('message', function(event) {
        const data = event.data;

        switch (data.action) {
            case 'open':
                openFrame(data.url);
                break;

            case 'close':
                closeFrame();
                break;
        }
    });

    // Open the iframe with the given URL
    function openFrame(url) {
        if (isOpen) return;
        isOpen = true;
        expectedUrl = url;

        // Show loading initially
        loading.classList.remove('hidden');
        frame.classList.remove('loaded');
        frame.src = 'about:blank';

        container.classList.remove('hidden');

        setTimeout(function() {
            loadUrlIntoFrame(url);
        }, 100);

        // Timeout to hide loading after 10 seconds regardless
        loadTimeout = setTimeout(function() {
            loading.classList.add('hidden');
            frame.classList.add('loaded');
        }, 10000);
    }

    // Handle iframe load
    frame.addEventListener('load', function() {
        if (expectedUrl && frame.srcdoc) {
            if (loadTimeout) {
                clearTimeout(loadTimeout);
                loadTimeout = null;
            }
            loading.classList.add('hidden');
            frame.classList.add('loaded');

            fetch('https://fiveroster-fivem/loaded', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({})
            }).catch(function() {});
        }
    });

    // Handle ESC key at window level
    window.addEventListener('keydown', function(event) {
        if ((event.key === 'Escape' || event.keyCode === 27) && isOpen) {
            event.preventDefault();
            event.stopPropagation();
            requestClose();
        }
    }, true);

    // Listen for ESC from iframe
    frame.addEventListener('load', function() {
        try {
            var iframeDoc = frame.contentDocument || frame.contentWindow.document;
            iframeDoc.addEventListener('keydown', function(event) {
                if (event.key === 'Escape' || event.keyCode === 27) {
                    event.preventDefault();
                    requestClose();
                }
            }, true);
        } catch (e) {
            // Cross-origin restriction - handled by injected script
        }
    });

    // Listen for messages from iframe
    window.addEventListener('message', function(event) {
        if (event.data && event.data.type === 'fiveroster') {
            switch (event.data.action) {
                case 'close':
                case 'submitted':
                    requestClose();
                    break;

                case 'navigate':
                    // Handle link clicks - fetch and inject new page
                    if (event.data.url) {
                        loading.classList.remove('hidden');
                        loadUrlIntoFrame(event.data.url);
                    }
                    break;

                case 'formSubmit':
                    // Handle form submissions
                    if (event.data.url) {
                        var url = event.data.url;
                        var method = event.data.method || 'GET';
                        var data = event.data.data || {};

                        loading.classList.remove('hidden');

                        if (method === 'GET') {
                            // Append data as query params
                            var params = new URLSearchParams(data).toString();
                            if (params) {
                                url += (url.indexOf('?') === -1 ? '?' : '&') + params;
                            }
                            loadUrlIntoFrame(url);
                        } else {
                            // POST request
                            fetch(url, {
                                method: 'POST',
                                headers: {
                                    'Content-Type': 'application/x-www-form-urlencoded',
                                },
                                body: new URLSearchParams(data).toString(),
                                credentials: 'include'
                            })
                            .then(function(response) {
                                // Check if redirected
                                if (response.redirected) {
                                    return fetch(response.url, { credentials: 'include' }).then(function(r) { return r.text(); });
                                }
                                return response.text();
                            })
                            .then(function(html) {
                                html = prepareHtml(html);
                                return inlineExternalScripts(html);
                            })
                            .then(function(html) {
                                frame.srcdoc = html;
                                loading.classList.add('hidden');
                            })
                            .catch(function(err) {
                                console.error('FiveRoster: Form submission failed', err);
                                loading.classList.add('hidden');
                                fetch('https://fiveroster-fivem/error', {
                                    method: 'POST',
                                    headers: { 'Content-Type': 'application/json' },
                                    body: JSON.stringify({})
                                }).catch(function() {});
                            });
                        }
                    }
                    break;
            }
        }
    });

    // Prevent context menu
    document.addEventListener('contextmenu', function(e) {
        e.preventDefault();
    });
})();
