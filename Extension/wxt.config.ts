import { defineConfig } from 'wxt';

const CHROME_EXTENSION_KEY =
  'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAuUTw4isNaNd7kVfEEsTp6vr+2iVj3CITO3iQtdFzQbfI1ap7hhdSwz0InU8zTpw4iNHCsd+sfGdwHJALZmWiKRYOses4TTafbWmpRtQc3KXPkPRfiTfmP3Yz2hOsUSfVDncVEn9ARTJiB69zYSTEsE8n41VwNt/PI9uNri7+zhlLxobKq9NElnSNQhto9BoAIYlu6uBhx7jLmV23dh2+cQTTihCNPAQUe5HqGdheuUT45M7/Tve34WCHTndd/36pv5TvKlKbnxv42O9h9aIaXFc1qb3IYOkkwshxibgfpJROutBluBIgeOjWp2uU9czPZau0zbzneuUwpXckqEceTQIDAQAB';

export default defineConfig({
  manifest: ({ browser }) => {
    const manifest: any = {
      name: 'Kodiz Download Manager',
      description: 'High-speed multi-connection download manager integration for macOS.',
      version: '0.1.0',
      permissions: [
        'downloads',
        'nativeMessaging',
        'cookies',
        'contextMenus',
        'storage',
        'webRequest',
        'scripting'
      ],
      host_permissions: ['<all_urls>'],
      browser_specific_settings: {
        gecko: {
          id: 'kodiz@kodiz.dev',
          strict_min_version: '109.0'
        }
      }
    };
    if (browser === 'chrome') {
      manifest.key = CHROME_EXTENSION_KEY;
    }
    return manifest;
  }
});
