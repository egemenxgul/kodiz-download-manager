# Spike 03: Safari Appex ↔ Ana Uygulama Unix Domain Socket İletişimi

## Amaç
Safari Web Extension (`.appex`) macOS gereği App Sandbox içinde çalışmak zorundadır. Ana uygulama ise yt-dlp, ffmpeg çalıştırmak ve tarayıcı manifestleri yazabilmek için Sandbox'sızdır. Bu iki sürecin App Group konteyneri üzerinden Unix domain socket ile haberleşmesini doğrulamak.

## Mimari
- **App Group:** `<TEAMID>.dev.kodiz.DownloadManager`
- **Soket Konumu:** `<AppGroupKonteyneri>/bridge.sock` (izinler: klasör `0700`, soket `0600`)
- **Protokol:** 4 bayt little-endian uzunluk önekli UTF-8 JSON.
- **Karşı Taraf Doğrulaması:** `LOCAL_PEERTOKEN` ile çağıran sürecin audit token'ı alınır ve `SecCodeCopyGuestWithAttributes` ile aynı Team ID ve beklenen bundle ID (`dev.kodiz.NativeHost` veya `dev.kodiz.DownloadManager.SafariExtension`) taşıdığı teyit edilir.
- **Uygulama Kapalıyken Devir:** Safari appex, sokete bağlanamazsa `NSWorkspace.shared.openApplication` kullanarak ana uygulamayı arka planda başlatır (`NSWorkspace.OpenConfiguration.promptsUserIfNeeded = false`, `.activates = false`).
