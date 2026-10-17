export default defineContentScript({
  matches: ['<all_urls>'],
  main() {
    const reportedMediaUrls = new Set<string>();

    // 1. X3: Detect Option (Alt) key clicks to bypass intercept
    window.addEventListener(
      'click',
      (e) => {
        const anchor = (e.target as HTMLElement)?.closest('a');
        if (!anchor || !anchor.href) return;

        if (e.altKey) {
          // User held Option (Alt) key: notify background to bypass for 5s
          browser.runtime.sendMessage({
            type: 'bypass_download',
            url: anchor.href,
            timestamp: Date.now()
          });
          return;
        }

        // X1: Safari fallback for links when browser.downloads is unavailable
        // Check if browser.downloads is supported or if anchor explicitly indicates download
        if (anchor.getAttribute('data-kodiz-bypassed') === 'true') {
          anchor.removeAttribute('data-kodiz-bypassed');
          return;
        }

        const isDownloadAttr = anchor.hasAttribute('download');
        const href = anchor.href;
        const isDownloadableExt = /\.(zip|dmg|pkg|iso|tar|gz|7z|rar|exe|bin|mp4|mkv|mov|mp3)$/i.test(href.split('?')[0]);

        if (isDownloadAttr || isDownloadableExt) {
          // If browser.downloads is not supported in this browser (Safari), intercept anchor click
          if (!browser.downloads) {
            e.preventDefault();
            browser.runtime
              .sendMessage({
                type: 'intercept_click',
                url: href,
                pageUrl: window.location.href,
                referrer: document.referrer
              })
              .then((res: any) => {
                if (!res || !res.ok) {
                  // Fallback: re-trigger click with bypass attribute
                  anchor.setAttribute('data-kodiz-bypassed', 'true');
                  anchor.click();
                }
              })
              .catch(() => {
                anchor.setAttribute('data-kodiz-bypassed', 'true');
                anchor.click();
              });
          }
        }
      },
      true
    );

    // 2. PerformanceObserver to detect streaming media (m3u8, mpd, ism)
    if ('PerformanceObserver' in window) {
      try {
        const observer = new PerformanceObserver((list) => {
          for (const entry of list.getEntries()) {
            const name = entry.name;
            if (
              (name.includes('.m3u8') || name.includes('.mpd') || name.includes('.ism')) &&
              !reportedMediaUrls.has(name)
            ) {
              reportedMediaUrls.add(name);
              browser.runtime.sendMessage({
                type: 'media_detected',
                url: name,
                pageUrl: window.location.href,
                title: document.title
              });
            }
          }
        });
        observer.observe({ entryTypes: ['resource'] });
      } catch {}
    }

    // 3. X5: Scan DOM for <video> and <audio> elements with 500ms debounce
    let debounceTimer: ReturnType<typeof setTimeout> | null = null;

    function scanMediaElements() {
      const media = document.querySelectorAll('video, audio, source');
      media.forEach((el) => {
        let src = '';
        if (el instanceof HTMLMediaElement) {
          src = el.currentSrc || el.src;
        } else if (el instanceof HTMLSourceElement) {
          src = el.src;
        }
        if (src && !src.startsWith('blob:') && !src.startsWith('data:') && !reportedMediaUrls.has(src)) {
          reportedMediaUrls.add(src);
          browser.runtime.sendMessage({
            type: 'media_detected',
            url: src,
            pageUrl: window.location.href,
            title: document.title
          });
        }
      });
    }

    scanMediaElements();

    const domObserver = new MutationObserver(() => {
      if (debounceTimer) clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => {
        scanMediaElements();
      }, 500); // 500ms debounce prevents message flooding
    });

    if (document.body) {
      domObserver.observe(document.body, { childList: true, subtree: true });
    }
  }
});
