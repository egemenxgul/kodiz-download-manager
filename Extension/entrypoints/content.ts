export default defineContentScript({
  matches: ['<all_urls>'],
  main() {
    // 1. Detect Option (Alt) key clicks to bypass intercept
    window.addEventListener('click', (e) => {
      if (e.altKey) {
        // Option key pressed: user wants to download in browser directly
        sessionStorage.setItem('kodiz_bypass_once', 'true');
      }
    }, true);

    // 2. PerformanceObserver to detect streaming media (m3u8, mpd) in all browsers
    if ('PerformanceObserver' in window) {
      try {
        const observer = new PerformanceObserver((list) => {
          for (const entry of list.getEntries()) {
            const name = entry.name;
            if (name.includes('.m3u8') || name.includes('.mpd') || name.includes('.ism')) {
              chrome.runtime.sendMessage({
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

    // 3. Scan DOM for <video> and <audio> elements
    function scanMediaElements() {
      const media = document.querySelectorAll('video, audio');
      media.forEach((el) => {
        const video = el as HTMLMediaElement;
        const src = video.currentSrc || video.src;
        if (src && !src.startsWith('blob:')) {
          chrome.runtime.sendMessage({
            type: 'media_detected',
            url: src,
            pageUrl: window.location.href,
            title: document.title
          });
        }
      });
    }

    scanMediaElements();
    const domObserver = new MutationObserver(() => scanMediaElements());
    domObserver.observe(document.body, { childList: true, subtree: true });
  }
});
