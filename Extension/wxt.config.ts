import { defineConfig } from 'wxt';

export default defineConfig({
  manifest: {
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
  }
});
