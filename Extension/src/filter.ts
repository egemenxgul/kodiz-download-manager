import { ExtensionConfig, DownloadItemLike, BypassRecord } from './types';

export function isSchemeSupported(url: string): boolean {
  if (!url) return false;
  try {
    const parsed = new URL(url);
    return parsed.protocol === 'http:' || parsed.protocol === 'https:';
  } catch {
    return false;
  }
}

export function extractExtension(url: string, filename?: string): string {
  if (filename) {
    const parts = filename.split('.');
    if (parts.length > 1) {
      const ext = parts.pop()?.trim().toLowerCase();
      if (ext && ext.length <= 10) return ext;
    }
  }

  try {
    const parsed = new URL(url);
    const pathname = parsed.pathname;
    const lastSlash = pathname.lastIndexOf('/');
    const filePart = lastSlash >= 0 ? pathname.substring(lastSlash + 1) : pathname;
    const parts = filePart.split('.');
    if (parts.length > 1) {
      const ext = parts.pop()?.trim().toLowerCase();
      if (ext && ext.length <= 10) return ext;
    }
  } catch {}

  return '';
}

export function isBypassed(
  url: string,
  bypasses: BypassRecord[],
  now: number = Date.now(),
  maxAgeMs: number = 5000
): boolean {
  return bypasses.some((b) => {
    if (now - b.timestamp > maxAgeMs) return false;
    return b.url === url || url.startsWith(b.url);
  });
}

export function shouldInterceptDownload(
  item: DownloadItemLike,
  config: ExtensionConfig,
  bypasses: BypassRecord[],
  now: number = Date.now()
): { intercept: boolean; reason: string } {
  if (!config.enabled) {
    return { intercept: false, reason: 'disabled' };
  }

  const targetUrl = item.finalUrl || item.url;
  if (!isSchemeSupported(targetUrl)) {
    return { intercept: false, reason: 'unsupported_scheme' };
  }

  if (item.incognito && !config.interceptIncognito) {
    return { intercept: false, reason: 'incognito_disabled' };
  }

  if (isBypassed(targetUrl, bypasses, now)) {
    return { intercept: false, reason: 'bypassed_by_user' };
  }

  try {
    const parsed = new URL(targetUrl);
    const hostname = parsed.hostname.toLowerCase();
    if (config.excludedDomains.some((d) => hostname === d || hostname.endsWith(`.${d}`))) {
      return { intercept: false, reason: 'domain_excluded' };
    }
  } catch {}

  const ext = extractExtension(targetUrl, item.filename);
  if (ext && config.excludedExtensions.includes(ext)) {
    return { intercept: false, reason: 'extension_excluded' };
  }

  // If MIME type is image or PDF, do not intercept
  if (item.mime) {
    const m = item.mime.toLowerCase();
    if (m.startsWith('image/') || m === 'application/pdf') {
      return { intercept: false, reason: 'mime_excluded' };
    }
  }

  // Size check: use totalBytes. If size is known and less than minSizeBytes, ignore
  if (typeof item.totalBytes === 'number' && item.totalBytes > 0 && item.totalBytes < config.minSizeBytes) {
    return { intercept: false, reason: 'below_min_size' };
  }

  return { intercept: true, reason: 'matched' };
}
