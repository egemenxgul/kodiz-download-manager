# Spike 04: Tarayıcı Native Messaging Host Manifest Yolları

## Hedef Yollar (`~/Library/Application Support/` altında)

| Tarayıcı | Manifest Klasörü | Durum |
|---|---|---|
| Google Chrome | `Google/Chrome/NativeMessagingHosts/` | Resmî belgeli |
| Chrome Beta | `Google/Chrome Beta/NativeMessagingHosts/` | Belgeli |
| Chrome Canary | `Google/Chrome Canary/NativeMessagingHosts/` | Belgeli |
| Chromium | `Chromium/NativeMessagingHosts/` | Belgeli |
| Brave Browser | `BraveSoftware/Brave-Browser/NativeMessagingHosts/` | Doğrulandı |
| Microsoft Edge | `Microsoft Edge/NativeMessagingHosts/` | Resmî belgeli |
| Opera | `com.operasoftware.Opera/NativeMessagingHosts/` ve Chrome yolu | Doğrulandı |
| Vivaldi | `Vivaldi/NativeMessagingHosts/` ve Chrome yolu | Doğrulandı |
| Mozilla Firefox | `Mozilla/NativeMessagingHosts/` | Resmî belgeli |

## Otomatik Onarım Mekanizması
Manifest içindeki `"path"` mutlak dosya yolu olmak zorundadır. Kullanıcı `Kodiz Download Manager.app` uygulamasını başka bir klasöre taşırsa, uygulama açılışında kendi konumunu `Bundle.main.bundleURL` ile kontrol eder ve tüm kurulu tarayıcıların manifest dosyalarını yeni mutlak yolla günceller.
