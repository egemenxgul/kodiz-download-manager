export interface ExtensionConfig {
  enabled: boolean;
  minSizeBytes: number;
  interceptExtensions: string[];
  excludedExtensions: string[];
  excludedDomains: string[];
  interceptIncognito: boolean;
}

export const DEFAULT_CONFIG: ExtensionConfig = {
  enabled: true,
  minSizeBytes: 1024 * 1024, // 1 MB
  interceptExtensions: [
    'zip', 'dmg', 'pkg', 'iso', 'tar', 'gz', 'tgz', '7z', 'rar', 'bz2', 'xz',
    'mp4', 'mkv', 'mov', 'avi', 'wmv', 'flv', 'webm',
    'mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg',
    'exe', 'bin', 'msi', 'apk', 'ipa'
  ],
  excludedExtensions: [
    'pdf', 'png', 'jpg', 'jpeg', 'webp', 'gif', 'svg', 'ico', 'bmp', 'tiff',
    'html', 'htm', 'css', 'js', 'json', 'xml', 'txt', 'csv'
  ],
  excludedDomains: [],
  interceptIncognito: false
};

export interface DownloadItemLike {
  id: number;
  url: string;
  finalUrl?: string;
  referrer?: string;
  filename?: string;
  totalBytes?: number;
  mime?: string;
  incognito?: boolean;
}

export interface BypassRecord {
  url: string;
  timestamp: number;
}

export interface MediaItem {
  url: string;
  title?: string;
  pageUrl: string;
  format?: string;
  detectedAt: number;
}
