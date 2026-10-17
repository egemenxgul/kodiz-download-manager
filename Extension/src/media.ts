import { MediaItem } from './types';

export function createMediaItem(
  url: string,
  pageUrl: string,
  title?: string,
  now: number = Date.now()
): MediaItem {
  let format: string | undefined;
  if (url.includes('.m3u8')) format = 'HLS (.m3u8)';
  else if (url.includes('.mpd')) format = 'DASH (.mpd)';
  else if (url.includes('.mp4')) format = 'MP4';
  else if (url.includes('.webm')) format = 'WebM';
  else if (url.includes('.mp3')) format = 'MP3';

  return {
    url,
    title: title || 'Media',
    pageUrl,
    format,
    detectedAt: now
  };
}

export function deduplicateMediaList(
  existing: MediaItem[],
  incoming: MediaItem
): MediaItem[] {
  if (existing.some((item) => item.url === incoming.url)) {
    return existing;
  }
  return [...existing, incoming];
}
