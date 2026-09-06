(function() {
    const container = document.getElementById('container');
    const frame = document.getElementById('fiveroster-frame');
    const loading = document.getElementById('loading');
    const closeBtn = document.getElementById('close-btn');

    let isOpen = false;
    let isClosing = false;
    let loadTimeout = null;
    let expectedUrl = null;
    const baseUrl = 'https://fiveroster.com';

    // Fetch URL and inject into iframe via srcdoc
    function loadUrlIntoFrame(url) {
        fetch(url, {
            referrerPolicy: 'no-referrer'
        })
            .then(function(response) {
                if (!response.ok) {
                    throw new Error('HTTP ' + response.status);
                }
                return response.text();
            })
            .then(function(html) {
                // Inject base tag for relative URLs
                if (html.indexOf('<head>') !== -1) {
                    html = html.replace('<head>', '<head><base href="' + baseUrl + '/">');
                } else if (html.indexOf('<HEAD>') !== -1) {
                    html = html.replace('<HEAD>', '<HEAD><base href="' + baseUrl + '/">');
                }

                // Inject navigation interceptor and ESC handler
                var injectedScript = '<script>' +
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

                if (html.indexOf('</body>') !== -1) {
                    html = html.replace('</body>', injectedScript + '</body>');
                } else if (html.indexOf('</BODY>') !== -1) {
                    html = html.replace('</BODY>', injectedScript + '</BODY>');
                } else {
                    html = html + injectedScript;
                }

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
        isClosing = false;
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
        if (!isOpen || isClosing) return;
        isClosing = true;

        // Send close callback to Lua - don't clear frame yet
        // Lua will send 'close' action back after releasing focus
        fetch('https://fiveroster-fivem/close', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        }).catch(function() {
            // If callback fails, force close locally
            closeFrame();
        });

        // Safety timeout - force close if Lua doesn't respond in 500ms
        setTimeout(function() {
            if (isClosing && isOpen) {
                closeFrame();
            }
        }, 500);
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
        isClosing = false;
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
                                referrerPolicy: 'no-referrer'
                            })
                            .then(function(response) {
                                // Check if redirected
                                if (response.redirected) {
                                    return fetch(response.url, { referrerPolicy: 'no-referrer' }).then(function(r) { return r.text(); });
                                }
                                return response.text();
                            })
                            .then(function(html) {
                                // Inject base tag
                                if (html.indexOf('<head>') !== -1) {
                                    html = html.replace('<head>', '<head><base href="' + baseUrl + '/">');
                                } else if (html.indexOf('<HEAD>') !== -1) {
                                    html = html.replace('<HEAD>', '<HEAD><base href="' + baseUrl + '/">');
                                }

                                // Inject scripts
                                var injectedScript = '<script>' +
                                    'document.addEventListener("keydown", function(e) {' +
                                    '  if (e.key === "Escape" || e.keyCode === 27) {' +
                                    '    e.preventDefault();' +
                                    '    window.parent.postMessage({type: "fiveroster", action: "close"}, "*");' +
                                    '  }' +
                                    '});' +
                                    'document.addEventListener("click", function(e) {' +
                                    '  var target = e.target.closest("a");' +
                                    '  if (target && target.href && !target.href.startsWith("javascript:")) {' +
                                    '    e.preventDefault();' +
                                    '    window.parent.postMessage({type: "fiveroster", action: "navigate", url: target.href}, "*");' +
                                    '  }' +
                                    '});' +
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

                                if (html.indexOf('</body>') !== -1) {
                                    html = html.replace('</body>', injectedScript + '</body>');
                                } else if (html.indexOf('</BODY>') !== -1) {
                                    html = html.replace('</BODY>', injectedScript + '</BODY>');
                                } else {
                                    html = html + injectedScript;
                                }

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

    // Click outside the tablet to close
    container.addEventListener('click', function(e) {
        if (e.target === container && isOpen) {
            requestClose();
        }
    });

    // Prevent context menu
    document.addEventListener('contextmenu', function(e) {
        e.preventDefault();
    });

    // ========================================================================
    // PRESENTATION PICKER
    // ========================================================================
    // Shown when a player casts a training presentation onto a screen in the
    // world. It is its own overlay, not part of the tablet: a player at a
    // briefing screen has not opened the tablet at all.

    const picker = document.getElementById('picker');
    const pickerList = document.getElementById('picker-list');
    const pickerScreen = document.getElementById('picker-screen');
    const pickerCloseBtn = document.getElementById('picker-close');

    let pickerOpen = false;

    function closePicker(notifyLua) {
        if (!pickerOpen) return;
        pickerOpen = false;
        picker.classList.add('hidden');
        pickerList.innerHTML = '';

        if (notifyLua) {
            fetch('https://fiveroster-fivem/closePicker', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({})
            }).catch(function() {});
        }
    }

    function castPresentation(uuid) {
        // Close first: the deck goes up on the screen, and the player needs
        // their controls back to drive it.
        closePicker(false);

        fetch('https://fiveroster-fivem/castPresentation', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ presentation_uuid: uuid })
        }).catch(function() {});
    }

    function buildPickerItem(presentation) {
        const item = document.createElement('li');
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'picker-item';

        const label = document.createElement('span');

        const name = document.createElement('span');
        name.className = 'picker-name';
        name.textContent = presentation.name || 'Untitled presentation';
        label.appendChild(name);

        // The roster is what tells two similarly named decks apart, so it is
        // shown whenever the backend sent one.
        if (presentation.roster_name) {
            const meta = document.createElement('span');
            meta.className = 'picker-meta';
            meta.textContent = presentation.roster_name;
            label.appendChild(meta);
        }

        const count = document.createElement('span');
        count.className = 'picker-count';
        const slides = Number(presentation.slide_count) || 0;
        count.textContent = slides === 1 ? '1 slide' : slides + ' slides';

        button.appendChild(label);
        button.appendChild(count);
        button.addEventListener('click', function() {
            castPresentation(presentation.presentation_uuid);
        });

        item.appendChild(button);
        return item;
    }

    function openPicker(presentations, screenLabel) {
        pickerScreen.textContent = screenLabel || 'Nearby screen';
        pickerList.innerHTML = '';

        if (!Array.isArray(presentations) || presentations.length === 0) {
            const empty = document.createElement('li');
            empty.className = 'picker-empty';
            empty.textContent = 'No presentations available to cast.';
            pickerList.appendChild(empty);
        } else {
            presentations.forEach(function(presentation) {
                pickerList.appendChild(buildPickerItem(presentation));
            });
        }

        pickerOpen = true;
        picker.classList.remove('hidden');

        const first = pickerList.querySelector('.picker-item');
        if (first) first.focus();
    }

    if (pickerCloseBtn) {
        pickerCloseBtn.addEventListener('click', function(e) {
            e.preventDefault();
            closePicker(true);
        });
    }

    // Clicking the backdrop dismisses, the same as the tablet.
    picker.addEventListener('click', function(e) {
        if (e.target === picker) closePicker(true);
    });

    // ESC while the picker is up closes the picker, not the tablet behind it.
    window.addEventListener('keydown', function(event) {
        if ((event.key === 'Escape' || event.keyCode === 27) && pickerOpen) {
            event.preventDefault();
            event.stopPropagation();
            closePicker(true);
        }
    }, true);

    window.addEventListener('message', function(event) {
        const data = event.data;
        if (!data) return;

        switch (data.action) {
            case 'openPicker':
                openPicker(data.presentations, data.screenLabel);
                break;

            case 'closePicker':
                closePicker(false);
                break;
        }
    });
})();
