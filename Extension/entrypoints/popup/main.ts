document.addEventListener('DOMContentLoaded', async () => {
  const toggle = document.getElementById('toggle-intercept') as HTMLInputElement;
  const downloadPageBtn = document.getElementById('download-current-page') as HTMLButtonElement;

  downloadPageBtn?.addEventListener('click', async () => {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab?.url) return;

    let cookies: any[] = [];
    try {
      cookies = await chrome.cookies.getAll({ url: tab.url });
    } catch {}

    const message = {
      v: 1,
      id: crypto.randomUUID(),
      type: 'media.download',
      payload: {
        url: tab.url,
        pageUrl: tab.url,
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

    chrome.runtime.sendNativeMessage('dev.kodiz.dm', message, (response) => {
      if (response?.ok) {
        window.close();
      }
    });
  });
});
