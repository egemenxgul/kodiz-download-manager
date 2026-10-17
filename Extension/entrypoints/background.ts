export default defineBackground(() => {
  const NATIVE_HOST_NAME = 'dev.kodiz.dm';
  let isInterceptEnabled = true;

  // Intercept downloads via chrome.downloads.onCreated
  chrome.downloads.onCreated.addListener(async (item) => {
    if (!isInterceptEnabled) return;

    const url = item.finalUrl || item.url;
    if (!url || (!url.startsWith('http://') && !url.startsWith('https://'))) {
      return;
    }

    // Minimum size filter (default 1MB if known)
    if (item.fileSize > 0 && item.fileSize < 1024 * 1024) {
      return;
    }

    // Pause download immediately while handing off to Kodiz
    try {
      await chrome.downloads.pause(item.id);
    } catch {
      return;
    }

    // Gather browser cookies for authentication
    let cookies: any[] = [];
    try {
      cookies = await chrome.cookies.getAll({ url });
    } catch {
      // Cookie access failed or restricted
    }

    const payload = {
      url,
      referrer: item.referrer || '',
      fileNameHint: item.filename || '',
      totalBytes: item.fileSize > 0 ? item.fileSize : null,
      mime: item.mime || '',
      userAgent: navigator.userAgent,
      cookies: cookies.map((c) => ({
        name: c.name,
        value: c.value,
        domain: c.domain,
        path: c.path,
        secure: c.secure,
        httpOnly: c.httpOnly,
        expirationDate: c.expirationDate
      })),
      incognito: item.incognito || false
    };

    const message = {
      v: 1,
      id: crypto.randomUUID(),
      type: 'download.add',
      browser: 'chromium',
      payload
    };

    // Send to native messaging host
    const timeout = setTimeout(() => {
      // Timeout fallback: resume in browser
      chrome.downloads.resume(item.id);
    }, 8000);

    try {
      chrome.runtime.sendNativeMessage(NATIVE_HOST_NAME, message, (response) => {
        clearTimeout(timeout);
        if (chrome.runtime.lastError || !response || !response.ok) {
          // If rejected or error, resume in browser
          chrome.downloads.resume(item.id);
        } else {
          // Kodiz accepted: cancel & remove from browser history
          chrome.downloads.cancel(item.id, () => {
            chrome.downloads.erase({ id: item.id });
          });
        }
      });
    } catch {
      clearTimeout(timeout);
      chrome.downloads.resume(item.id);
    }
  });

  // Setup context menus
  chrome.runtime.onInstalled.addListener(() => {
    chrome.contextMenus.create({
      id: 'kodiz-download-link',
      title: 'Kodiz ile İndir',
      contexts: ['link']
    });

    chrome.contextMenus.create({
      id: 'kodiz-download-media',
      title: 'Bu Medyayı Kodiz ile İndir',
      contexts: ['video', 'audio']
    });
  });

  chrome.contextMenus.onClicked.addListener(async (info, tab) => {
    const targetUrl = info.linkUrl || info.srcUrl || info.pageUrl;
    if (!targetUrl) return;

    let cookies: any[] = [];
    try {
      cookies = await chrome.cookies.getAll({ url: targetUrl });
    } catch {}

    const message = {
      v: 1,
      id: crypto.randomUUID(),
      type: 'download.add',
      payload: {
        url: targetUrl,
        pageUrl: tab?.url || '',
        referrer: tab?.url || '',
        userAgent: navigator.userAgent,
        cookies: cookies.map((c) => ({
          name: c.name,
          value: c.value,
          domain: c.domain,
          path: c.path,
          secure: c.secure,
          httpOnly: c.httpOnly
        }))
      }
    };

    chrome.runtime.sendNativeMessage(NATIVE_HOST_NAME, message);
  });
});
