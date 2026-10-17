import { DEFAULT_CONFIG, ExtensionConfig, BypassRecord, MediaItem } from '../src/types';
import { shouldInterceptDownload } from '../src/filter';
import { createMediaItem, deduplicateMediaList } from '../src/media';

export default defineBackground(() => {
  const NATIVE_HOST_NAME = 'dev.kodiz.dm';

  let currentConfig: ExtensionConfig = { ...DEFAULT_CONFIG };
  const bypassRecords: BypassRecord[] = [];
  const tabMediaMap = new Map<number, MediaItem[]>();

  // 1. Load config from storage and sync with native host
  async function loadConfig() {
    try {
      const data = await browser.storage.local.get('kodiz_config');
      if (data && data.kodiz_config) {
        currentConfig = { ...DEFAULT_CONFIG, ...data.kodiz_config };
      }
    } catch {}

    // Request latest config from Kodiz Native Host
    try {
      const message = {
        v: 1,
        id: crypto.randomUUID(),
        type: 'getConfig'
      };
      const response = (await browser.runtime.sendNativeMessage(NATIVE_HOST_NAME, message)) as any;
      if (response && response.ok && response.config) {
        currentConfig = { ...currentConfig, ...response.config };
        await browser.storage.local.set({ kodiz_config: currentConfig });
      }
    } catch {
      // Native host not yet running or unavailable; use stored/default config
    }
  }

  loadConfig();

  // Listen to configuration updates from storage (e.g. from popup toggle)
  browser.storage.onChanged.addListener((changes, area) => {
    if (area === 'local' && changes.kodiz_config) {
      currentConfig = { ...DEFAULT_CONFIG, ...(changes.kodiz_config.newValue as ExtensionConfig) };
    }
  });

  // 2. Intercept downloads via browser.downloads (Chromium & Firefox)
  // X1: In Safari, browser.downloads does not exist
  if (browser.downloads && browser.downloads.onCreated) {
    browser.downloads.onCreated.addListener(async (item) => {
      const itemAny = item as any;
      const targetUrl = itemAny.finalUrl || item.url;
      const filterResult = shouldInterceptDownload(
        {
          id: item.id,
          url: item.url,
          finalUrl: itemAny.finalUrl,
          referrer: item.referrer,
          filename: item.filename,
          totalBytes: item.totalBytes,
          mime: item.mime,
          incognito: item.incognito
        },
        currentConfig,
        bypassRecords
      );

      if (!filterResult.intercept) {
        return;
      }

      // Pause download immediately while handing off to Kodiz
      try {
        await browser.downloads.pause(item.id);
      } catch {
        return;
      }
      let cookies: any[] = [];
      try {
        cookies = await browser.cookies.getAll({ url: targetUrl });
      } catch {}

      const payload = {
        url: targetUrl,
        referrer: item.referrer || '',
        fileNameHint: item.filename || '',
        totalBytes: typeof item.totalBytes === 'number' && item.totalBytes > 0 ? item.totalBytes : null,
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
        payload
      };

      // X7: Prevent race between 10s timeout and bridge response with settled flag
      let settled = false;

      const timeoutId = setTimeout(async () => {
        if (settled) return;
        settled = true;
        try {
          await browser.downloads.resume(item.id);
        } catch {}
      }, 10000); // 10s timeout

      try {
        const response = (await browser.runtime.sendNativeMessage(NATIVE_HOST_NAME, message)) as any;
        if (settled) return;
        settled = true;
        clearTimeout(timeoutId);

        if (response && response.ok) {
          // Kodiz accepted: cancel & remove from browser history
          await browser.downloads.cancel(item.id);
          try {
            await browser.downloads.erase({ id: item.id });
          } catch {}
        } else {
          // Kodiz rejected: resume in browser
          await browser.downloads.resume(item.id);
        }
      } catch {
        if (!settled) {
          settled = true;
          clearTimeout(timeoutId);
          try {
            await browser.downloads.resume(item.id);
          } catch {}
        }
      }
    });
  }

  // 3. Message handler for content script and popup
  browser.runtime.onMessage.addListener(async (msg: any, sender: any) => {
    // X3: Option key bypass recorded from content script
    if (msg.type === 'bypass_download' && msg.url) {
      bypassRecords.push({
        url: msg.url,
        timestamp: msg.timestamp || Date.now()
      });
      // Prune records older than 10 seconds
      const now = Date.now();
      while (bypassRecords.length > 0 && now - bypassRecords[0].timestamp > 10000) {
        bypassRecords.shift();
      }
      return { ok: true };
    }

    // X5: Streaming media detected by content script
    if (msg.type === 'media_detected' && msg.url) {
      const tabId = sender.tab?.id;
      if (tabId !== undefined) {
        const existing = tabMediaMap.get(tabId) || [];
        const incoming = createMediaItem(msg.url, msg.pageUrl || sender.tab?.url || '', msg.title);
        const updated = deduplicateMediaList(existing, incoming);
        tabMediaMap.set(tabId, updated);

        // Update action badge with count
        if (browser.action && browser.action.setBadgeText) {
          const text = updated.length > 0 ? String(updated.length) : '';
          browser.action.setBadgeText({ tabId, text });
          browser.action.setBadgeBackgroundColor({ tabId, color: '#3b82f6' });
        }
      }
      return { ok: true };
    }

    // Fetch media items for a tab (requested by popup)
    if (msg.type === 'get_tab_media') {
      const tabId = msg.tabId;
      return { media: tabMediaMap.get(tabId) || [] };
    }

    // X1: Safari fallback for intercepted anchor clicks
    if (msg.type === 'intercept_click' && msg.url) {
      let cookies: any[] = [];
      try {
        cookies = await browser.cookies.getAll({ url: msg.url });
      } catch {}

      const message = {
        v: 1,
        id: crypto.randomUUID(),
        type: 'download.add',
        payload: {
          url: msg.url,
          pageUrl: msg.pageUrl || '',
          referrer: msg.referrer || '',
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

      try {
        const res = (await browser.runtime.sendNativeMessage(NATIVE_HOST_NAME, message)) as any;
        return { ok: res?.ok === true, downloadId: res?.downloadId };
      } catch (err: any) {
        return { ok: false, reason: err?.message };
      }
    }

    return undefined;
  });

  // Clean up media list when tab is closed or navigated
  browser.tabs.onRemoved.addListener((tabId) => {
    tabMediaMap.delete(tabId);
  });

  browser.tabs.onUpdated.addListener((tabId, changeInfo) => {
    if (changeInfo.status === 'loading') {
      tabMediaMap.delete(tabId);
      if (browser.action && browser.action.setBadgeText) {
        browser.action.setBadgeText({ tabId, text: '' });
      }
    }
  });

  // 4. Setup Context Menus
  browser.runtime.onInstalled.addListener(() => {
    if (browser.contextMenus && browser.contextMenus.create) {
      browser.contextMenus.create({
        id: 'kodiz-download-link',
        title: 'Kodiz ile İndir',
        contexts: ['link']
      });

      browser.contextMenus.create({
        id: 'kodiz-download-media',
        title: 'Bu Medyayı Kodiz ile İndir',
        contexts: ['video', 'audio']
      });
    }
  });

  if (browser.contextMenus && browser.contextMenus.onClicked) {
    browser.contextMenus.onClicked.addListener(async (info, tab) => {
      const targetUrl = info.linkUrl || info.srcUrl || info.pageUrl;
      if (!targetUrl) return;

      let cookies: any[] = [];
      try {
        cookies = await browser.cookies.getAll({ url: targetUrl });
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

      try {
        await browser.runtime.sendNativeMessage(NATIVE_HOST_NAME, message);
      } catch {}
    });
  }
});
