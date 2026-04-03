(function() {
    const container = document.getElementById('container');
    const frame = document.getElementById('fiveroster-frame');
    const loading = document.getElementById('loading');
    const closeBtn = document.getElementById('close-btn');

    let isOpen = false;
    let loadTimeout = null;

    // Close the NUI
    function closeFrame() {
        isOpen = false;

        if (loadTimeout) {
            clearTimeout(loadTimeout);
            loadTimeout = null;
        }

        container.classList.add('hidden');
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

        // Show loading initially
        loading.classList.remove('hidden');
        frame.classList.remove('loaded');
        frame.src = 'about:blank';

        container.classList.remove('hidden');

        // Load the embed URL directly in the iframe
        setTimeout(function() {
            frame.src = url;
        }, 100);

        // Timeout to hide loading after 10 seconds regardless
        loadTimeout = setTimeout(function() {
            loading.classList.add('hidden');
            frame.classList.add('loaded');
        }, 10000);
    }

    // Handle iframe load
    frame.addEventListener('load', function() {
        if (isOpen && frame.src !== 'about:blank') {
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
            // Cross-origin restriction - ESC handled at window level
        }
    });

    // Listen for close messages from iframe (if FiveRoster sends them)
    window.addEventListener('message', function(event) {
        if (event.data && event.data.type === 'fiveroster') {
            switch (event.data.action) {
                case 'close':
                case 'submitted':
                    requestClose();
                    break;
            }
        }
    });

    // Prevent context menu
    document.addEventListener('contextmenu', function(e) {
        e.preventDefault();
    });
})();
