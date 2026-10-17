import { describe, it, expect } from 'vitest';
import { createMediaItem, deduplicateMediaList } from '../src/media';
import { MediaItem } from '../src/types';

describe('media.ts', () => {
  it('creates media item with detected format (X5)', () => {
    const item = createMediaItem(
      'https://video.example.com/playlist.m3u8?token=xyz',
      'https://example.com/watch',
      'Example Video'
    );
    expect(item.format).toBe('HLS (.m3u8)');
    expect(item.title).toBe('Example Video');
    expect(item.pageUrl).toBe('https://example.com/watch');
  });

  it('deduplicates media items with identical URLs (X5)', () => {
    const item1 = createMediaItem('https://video.example.com/stream.m3u8', 'https://example.com');
    const item2 = createMediaItem('https://video.example.com/stream.m3u8', 'https://example.com');
    const item3 = createMediaItem('https://video.example.com/other.mp4', 'https://example.com');

    let list: MediaItem[] = [];
    list = deduplicateMediaList(list, item1);
    expect(list.length).toBe(1);

    list = deduplicateMediaList(list, item2);
    expect(list.length).toBe(1); // Not duplicated

    list = deduplicateMediaList(list, item3);
    expect(list.length).toBe(2);
  });
});
