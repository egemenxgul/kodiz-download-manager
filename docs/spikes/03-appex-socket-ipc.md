# Spike 03: Safari Appex ↔ Ana Uygulama Unix Domain Socket İletişimi

> **Durum:** Kısmen doğrulandı (kanıt: BridgeServer, UnixSocketClient, BridgeSocketPath soket iletişimi, 50 eşzamanlı istek ve framing testleri `BridgeProtocolTests` altında DOĞRULANDI; Safari extension'ın sandbox altında canlı Safari tarayıcısında çalışması Apple Developer hesabı/imzalı Appex gerektirdiği için DOĞRULANMADI).

## Amaç
Safari Web Extension (`.appex`) macOS gereği App Sandbox içinde çalışmak zorundadır. Ana uygulama ise yt-dlp çalıştırmak ve tarayıcı manifestleri yazabilmek için Sandbox'sızdır. Bu iki sürecin App Group konteyneri üzerinden Unix domain socket ile haberleşmesini doğrulamak.

## Mimari
- **App Group:** `<TEAMID>.dev.kodiz.DownloadManager` (veya Team ID yoksa `dev.kodiz.DownloadManager`)
- **Soket Konumu:** `<AppGroupKonteyneri>/bridge.sock` veya fallback olarak `~/Library/Application Support/Kodiz Download Manager/bridge.sock` (izinler: klasör `0700`, soket `0600`).
- **Protokol:** 4 bayt little-endian uzunluk önekli UTF-8 JSON.
- **Karşı Taraf Doğrulaması:** `LOCAL_PEERTOKEN` ile çağıran sürecin audit token'ı alınır ve `SecCodeCopyGuestWithAttributes` ile aynı Team ID ve beklenen bundle ID (`dev.kodiz.NativeHost` veya `dev.kodiz.DownloadManager.SafariExtension`) taşıdığı teyit edilir (Debug derlemesinde `KODIZ_ALLOW_UNSIGNED_BRIDGE=1` kaçış yolu mevcuttur).
- **Uygulama Kapalıyken Devir:** Safari appex ve NMH, sokete bağlanamazsa `NSWorkspace.shared.openApplication` kullanarak ana uygulamayı arka planda başlatır (`.activates = false`, `arguments: ["--background"]`).
