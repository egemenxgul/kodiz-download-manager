# Kodiz Download Manager — İlerleme Raporu (PROGRESS.md)

**Son Güncelleme:** 17 Ekim 2026 (Başlangıç)
**Çalışma Dalı:** `fix/engine-and-bridge`

---

## Sahibin Kararı Gereken Konular

1. **Apple Developer Program & Team ID:**
   - App Group öneki (`<TEAMID>.dev.kodiz.DownloadManager`), Safari Extension (appex) sandbox ve Developer ID / Notarization için geçerli bir Team ID ve Apple Developer hesabı gerekmektedir.
   - Şu anki durum: Team ID bilinmediğinden varsayılan `dev.kodiz.DownloadManager` sabiti ile devam ediliyor ve DEBUG derlemelerde imzasız köprüye izin veren kaçış yolu (`KODIZ_ALLOW_UNSIGNED_BRIDGE=1`) sağlanıyor.
2. **Bundle Identifier & Alan Adı:**
   - `dev.kodiz.DownloadManager` geçici olarak kullanılmaktadır. Nihai domain/bundle ID kararı bekleniyor.
3. **Chromium Eklentisi Sabit RSA Anahtarı:**
   - Eklenti ID'sinin sabit kalması için RSA-2048 anahtar çifti üretilecek, açık anahtar manifest'e eklenecektir. Özel anahtar (`.pem`) repoya KESİNLİKLE EKLENMEYECEK (`.gitignore`'a dahil edilecek). Bu anahtarın nerede/nasıl saklanacağı sahibin kararına bağlıdır.
4. **Notarization & CI Secrets:**
   - Apple Developer hesabı gerektiren `notarytool` kimlik bilgileri (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`) ve Sparkle imza anahtarları repo sahibinin ortamında sağlanmalıdır.

---

## Başlangıç Durumu ve Temel Doğrulama

- Başlangıç commit'i / dalı oluşturuldu: `fix/engine-and-bridge`.
- Temel test ortamı doğrulandı:
  - Komut: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/KodizKit --scratch-path /tmp/kodiz-kk-build`
  - Sonuç: 14 birim testi başarılı (KodizStoreTests: 2, KodizMediaTests: 4, KodizEngineTests: 6, KodizBridgeProtocolTests: 2).
- Tespit edilen inceleme bulguları (E1–E9, A1–A5, K1–K6, X1–X8, B1–B4) aşamalar halinde ele alınacaktır.

---

## Aşama Durumları

- [x] **AŞAMA 1 — Test Altyapısı**
  - **Yapılanlar:**
    - `TestHTTPServer` baştan Network.framework (NWListener/NWConnection) ile HTTP/1.1 keep-alive ve `Content-Length` uyumlu olarak yazıldı.
    - `DeterministicData` ile rastgele seed'li, streaming, deterministik bayt üretimi ve SHA-256 doğrulama altyapısı kuruldu.
    - 10 test profili eksiksiz uygulandı: `range`, `norange`, `unknown-length`, `ratelimit`, `flaky`, `slow`, `etag-change`, `redirect`, `gzip-force`, `disposition`.
    - `TestHTTPServerTests` içinde 10 birim testi yazılarak her profil doğrulandı.
    - `Tools/TestServer` bağımsız çalıştırılabilir CLI olarak güncellendi ve derlendi.
  - **Çalıştırılan Testler & Kanıt:**
    - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/KodizKit --filter TestHTTPServerTests --scratch-path /tmp/kodiz-kk-build`
    - Sonuç: 10/10 test başarılı (testDeterministicSHA256Consistency, testDispositionProfile, testETagChangeProfile, testFlakyProfile, testGzipForceProfile, testNoRangeProfile, testRangeProfile, testRateLimitProfile, testRedirectProfile, testUnknownLengthProfile). Toplam süre: 0.46 sn.
    - Toplam KodizKit testi: 24/24 başarılı (0 hata).
    - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path Tools/TestServer --scratch-path /tmp/kodiz-ts-build` -> BUILD SUCCESS.
  - **Sırada:** AŞAMA 2 — İndirme motoru düzeltmeleri (E1–E9, T1–T13).

- [ ] **AŞAMA 2 — İndirme Motoru Düzeltmeleri (E1–E9, T1–T13)**
- [ ] **AŞAMA 3 — Kalıcılık ve Uygulama Katmanı (A1–A5)**
- [ ] **AŞAMA 4 — Köprü ve Native Host (K1–K6, A3)**
- [ ] **AŞAMA 5 — Eklenti (X1–X8)**
- [ ] **AŞAMA 6 — Betikler, CI ve Belgeler (B1–B4)**
