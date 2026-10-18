import { DEFAULT_CONFIG, ExtensionConfig, MediaItem } from '../../src/types';

document.addEventListener('DOMContentLoaded', async () => {
  const toggle = document.getElementById('toggle-intercept') as HTMLInputElement;
  const statusBadge = document.querySelector('.status-badge') as HTMLElement;
  const statusDot = document.querySelector('.status-dot') as HTMLElement;
  const statusText = statusBadge?.querySelector('span');
  const downloadPageBtn = document.getElementById('download-current-page') as HTMLButtonElement;
  const mediaContainer = document.getElementById('media-container') as HTMLElement;
  const mediaList = document.getElementById('media-list') as HTMLElement;

  const NATIVE_HOST_NAME = 'dev.kodiz.dm';

  // 1. X4: Initialize toggle switch from storage
  try {
    const data = (await browser.storage.local.get('kodiz_config')) as any;
    const config: ExtensionConfig = data?.kodiz_config || DEFAULT_CONFIG;
    if (toggle) {
      toggle.checked = config.enabled;
    }
  } catch {}

  toggle?.addEventListener('change', async () => {
    try {
      const data = (await browser.storage.local.get('kodiz_config')) as any;
      const config: ExtensionConfig = data?.kodiz_config || { ...DEFAULT_CONFIG };
      config.enabled = toggle.checked;
      await browser.storage.local.set({ kodiz_config: config });
    } catch {}
  });

  // 2. Check connection status with Kodiz
  try {
    const helloMsg = { v: 1, id: crypto.randomUUID(), type: 'status' };
    const res = (await browser.runtime.sendNativeMessage(NATIVE_HOST_NAME, helloMsg)) as any;
    if (res && res.ok) {
      if (statusText) statusText.textContent = 'Bağlı';
      if (statusDot) statusDot.style.background = '#10b981';
      if (statusBadge) statusBadge.style.color = '#10b981';
    } else {
      throw new Error();
    }
  } catch {
    if (statusText) statusText.textContent = 'Bağlantı Yok';
    if (statusDot) statusDot.style.background = '#ef4444';
    if (statusBadge) {
      statusBadge.style.color = '#ef4444';
      statusBadge.style.background = 'rgba(239, 68, 68, 0.15)';
    }
  }

  // 3. X5: Load detected media for the active tab
  const [activeTab] = await browser.tabs.query({ active: true, currentWindow: true });
  if (activeTab?.id !== undefined) {
    try {
      const response = (await browser.runtime.sendMessage({
        type: 'get_tab_media',
        tabId: activeTab.id
      })) as any;

      const media: MediaItem[] = response?.media || [];
      if (media.length > 0 && mediaContainer && mediaList) {
        mediaContainer.style.display = 'block';
        mediaList.innerHTML = '';

        media.forEach((item) => {
          const itemEl = document.createElement('div');
          itemEl.className = 'media-item';

          const labelEl = document.createElement('div');
          labelEl.className = 'media-url';
          labelEl.title = item.url;
          labelEl.textContent = `${item.format ? `[${item.format}] ` : ''}${item.title || item.url}`;

          const dlBtn = document.createElement('button');
          dlBtn.className = 'btn-small';
          dlBtn.textContent = 'İndir';
          dlBtn.addEventListener('click', async () => {
            let cookies: any[] = [];
            try {
              cookies = await browser.cookies.getAll({ url: item.url });
            } catch {}

            const msg = {
              v: 1,
              id: crypto.randomUUID(),
              type: 'download.add',
              payload: {
                url: item.url,
                pageUrl: item.pageUrl,
                referrer: item.pageUrl,
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
              await browser.runtime.sendNativeMessage(NATIVE_HOST_NAME, msg);
              dlBtn.textContent = 'Eklendi ✓';
              dlBtn.disabled = true;
            } catch {}
          });

          itemEl.appendChild(labelEl);
          itemEl.appendChild(dlBtn);
          mediaList.appendChild(itemEl);
        });
      }
    } catch {}
  }

  // 4. Download Current Page Button
  downloadPageBtn?.addEventListener('click', async () => {
    if (!activeTab?.url) return;

    let cookies: any[] = [];
    try {
      cookies = await browser.cookies.getAll({ url: activeTab.url });
    } catch {}

    const message = {
      v: 1,
      id: crypto.randomUUID(),
      type: 'media.download',
      payload: {
        url: activeTab.url,
        pageUrl: activeTab.url,
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

    let reason = 'Kodiz uygulamasına ulaşılamadı';
    try {
      const response = (await browser.runtime.sendNativeMessage(NATIVE_HOST_NAME, message)) as any;
      if (response?.ok) {
        window.close();
        return;
      }
      if (response?.reason) reason = response.reason;
    } catch {}

    // Show why nothing happened instead of failing silently
    const original = downloadPageBtn.textContent;
    downloadPageBtn.textContent = reason;
    downloadPageBtn.disabled = true;
    setTimeout(() => {
      downloadPageBtn.textContent = original;
      downloadPageBtn.disabled = false;
    }, 3000);
  });
});
