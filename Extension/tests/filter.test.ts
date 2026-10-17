import { describe, it, expect } from 'vitest';
import {
  isSchemeSupported,
  extractExtension,
  isBypassed,
  shouldInterceptDownload
} from '../src/filter';
import { DEFAULT_CONFIG, DownloadItemLike } from '../src/types';

describe('filter.ts', () => {
  describe('isSchemeSupported', () => {
    it('accepts http and https', () => {
      expect(isSchemeSupported('http://example.com/file.zip')).toBe(true);
      expect(isSchemeSupported('https://example.com/file.zip')).toBe(true);
    });

    it('rejects blob, data, and file schemes (X8)', () => {
      expect(isSchemeSupported('blob:http://example.com/uuid')).toBe(false);
      expect(isSchemeSupported('data:application/octet-stream;base64,...')).toBe(false);
      expect(isSchemeSupported('file:///Users/test/file.zip')).toBe(false);
      expect(isSchemeSupported('javascript:void(0)')).toBe(false);
      expect(isSchemeSupported('')).toBe(false);
    });
  });

  describe('extractExtension', () => {
    it('extracts from filename first', () => {
      expect(extractExtension('https://example.com/download?id=123', 'archive.tar.gz')).toBe('gz');
      expect(extractExtension('https://example.com/file', 'setup.dmg')).toBe('dmg');
    });

    it('extracts from url pathname when filename missing', () => {
      expect(extractExtension('https://example.com/path/to/archive.zip?auth=token')).toBe('zip');
      expect(extractExtension('https://example.com/video.mp4#t=10')).toBe('mp4');
    });
  });

  describe('isBypassed (X3)', () => {
    const now = 10000;
    it('returns true if URL was bypassed within 5s', () => {
      const bypasses = [{ url: 'https://example.com/file.zip', timestamp: now - 2000 }];
      expect(isBypassed('https://example.com/file.zip', bypasses, now)).toBe(true);
    });

    it('returns false if bypass expired (> 5s)', () => {
      const bypasses = [{ url: 'https://example.com/file.zip', timestamp: now - 5500 }];
      expect(isBypassed('https://example.com/file.zip', bypasses, now)).toBe(false);
    });
  });

  describe('shouldInterceptDownload', () => {
    const config = { ...DEFAULT_CONFIG };

    it('intercepts standard zip download above 1MB', () => {
      const item: DownloadItemLike = {
        id: 1,
        url: 'https://example.com/large.zip',
        totalBytes: 50 * 1024 * 1024
      };
      const res = shouldInterceptDownload(item, config, []);
      expect(res.intercept).toBe(true);
    });

    it('rejects download when extension disabled (X4)', () => {
      const item: DownloadItemLike = {
        id: 1,
        url: 'https://example.com/large.zip',
        totalBytes: 50 * 1024 * 1024
      };
      const res = shouldInterceptDownload(item, { ...config, enabled: false }, []);
      expect(res.intercept).toBe(false);
      expect(res.reason).toBe('disabled');
    });

    it('rejects file smaller than minSizeBytes (X2)', () => {
      const item: DownloadItemLike = {
        id: 1,
        url: 'https://example.com/small.zip',
        totalBytes: 500 * 1024 // 500 KB < 1 MB
      };
      const res = shouldInterceptDownload(item, config, []);
      expect(res.intercept).toBe(false);
      expect(res.reason).toBe('below_min_size');
    });

    it('intercepts unknown size (totalBytes undefined or -1)', () => {
      const item: DownloadItemLike = {
        id: 1,
        url: 'https://example.com/stream.bin'
      };
      const res = shouldInterceptDownload(item, config, []);
      expect(res.intercept).toBe(true);
    });

    it('rejects excluded extensions (e.g. PDF, image) (X2)', () => {
      const item: DownloadItemLike = {
        id: 1,
        url: 'https://example.com/document.pdf',
        totalBytes: 10 * 1024 * 1024
      };
      const res = shouldInterceptDownload(item, config, []);
      expect(res.intercept).toBe(false);
      expect(res.reason).toBe('extension_excluded');
    });

    it('rejects image MIME types (X2)', () => {
      const item: DownloadItemLike = {
        id: 1,
        url: 'https://example.com/download_file',
        mime: 'image/png',
        totalBytes: 5 * 1024 * 1024
      };
      const res = shouldInterceptDownload(item, config, []);
      expect(res.intercept).toBe(false);
      expect(res.reason).toBe('mime_excluded');
    });

    it('rejects incognito download when interceptIncognito is false (X6)', () => {
      const item: DownloadItemLike = {
        id: 1,
        url: 'https://example.com/private.zip',
        totalBytes: 10 * 1024 * 1024,
        incognito: true
      };
      const res = shouldInterceptDownload(item, { ...config, interceptIncognito: false }, []);
      expect(res.intercept).toBe(false);
      expect(res.reason).toBe('incognito_disabled');
    });

    it('allows incognito download when interceptIncognito is true (X6)', () => {
      const item: DownloadItemLike = {
        id: 1,
        url: 'https://example.com/private.zip',
        totalBytes: 10 * 1024 * 1024,
        incognito: true
      };
      const res = shouldInterceptDownload(item, { ...config, interceptIncognito: true }, []);
      expect(res.intercept).toBe(true);
    });

    it('rejects bypassed download (X3)', () => {
      const item: DownloadItemLike = {
        id: 1,
        url: 'https://example.com/bypassed.zip',
        totalBytes: 10 * 1024 * 1024
      };
      const now = 20000;
      const res = shouldInterceptDownload(
        item,
        config,
        [{ url: 'https://example.com/bypassed.zip', timestamp: now - 1000 }],
        now
      );
      expect(res.intercept).toBe(false);
      expect(res.reason).toBe('bypassed_by_user');
    });
  });
});
