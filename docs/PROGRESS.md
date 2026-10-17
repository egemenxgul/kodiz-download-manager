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

- [x] **AŞAMA 2 — İndirme Motoru Düzeltmeleri (E1–E9, T1–T13)**
  - **Yapılanlar:**
    - **E1 & E2 (ConnectionWorker):** `bytes(for:)` ve bayt-bayt döngü tamamen kaldırıldı. `URLSessionDataDelegate` streaming yapısına geçildi; veriler 1 MiB'lık tamponlarda toplanıp tek bir `pwrite` ile diske yazılıyor. `timeoutIntervalForRequest = 30` (boşta okuma süresi), `timeoutIntervalForResource = 604800` (7 gün) yapıldı.
    - **E3 & E5 (SegmentPlanner):** Hata alan parçaları yeniden kuyruğa alan üstel geri çekilmeli (`Retry-After` öncelikli) durum makinesi uygulandı. Parça başına 10 deneme sınırı kondu. Açık uçlu parçalarda (`end == -1`) `isCompleted` hatası düzeltildi; yalnızca açık EOF durumunda tamamlanma kabul ediliyor. İş çalma için ucuz parça sınırı sorgusu (`getSegmentEnd`) ve sınır kırpma eklendi.
    - **E4 (Yanıt doğrulama):** Range istendiğinde yalnızca `206 Partial Content` kabul ediliyor; `Content-Range` başlangıcı ve probe boyutu doğrulanıyor. `If-Range` varken gelen `200` yanıtı `DownloadError.fileChanged` hatası fırlatıyor. `If-Range` yokken gelen `200` yanıtı `serverDoesNotSupportRange` hatası fırlatıyor ve asla parça ofsetine yazılmıyor.
    - **E6 (İşçi yaşam döngüsü):** Delegate üzerinden kontrolsüz Task başlatma kodları tamamen temizlendi. İşçiler `withTaskGroup` altında tekil `while let seg = await planner.allocateWork() { ... }` döngüsüyle yapısal olarak yönetiliyor.
    - **E7 (Duraklat/Sürdür/İptal):** `pause()` ile tüm tamponlar yazılıp `fsync` yapılıyor ve parça durumu dışarı aktarılıyor. `resume()` kaydedilen parçalardan `If-Range` ile oturumları tazeleyerek devam ediyor. `cancel()` `.kodizpart` dosyasını siliyor.
    - **E8 (Başlıklar & Çerezler):** `DownloadRequestOptions` yapısı eklendi; User-Agent, Referer, domain/path/secure eşleşmeli Cookie başlığı ve `Accept-Encoding: identity` hem probe hem tüm işçi isteklerine aktarıldı.
    - **E9 (AIMD & Hız Sınırı):** 429/503 yanıtlarında `AIMDController.recordCongestion` çağrılarak bağlantı sayısı düşürülüyor. `RateLimiter` tampon yazılmadan önce token çekiyor.
    - **DownloadCheckpointSink:** Motor GRDB'den bağımsızlaştırıldı, protokol tabanlı checkpoint (2 sn veya 16 MiB) altyapısı kuruldu.
    - **Bitiş & Metadata:** Dosya bitiminde `fsync` ve atomik dosya adı değişikliği yapılıyor. `kdm-cli` yeni motora ve `FileMetadata` karantina/WhereFroms/Dock zıplatma çağrılarına uyarlandı.
  - **Çalıştırılan Testler & Kanıt:**
    - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/KodizKit --scratch-path /tmp/kodiz-kk-build`
    - Sonuç: 35/35 test başarılı (0 hata):
      - `EngineIntegrationTests` (13 test):
        - T1 (range, 8 bağlantı, 256 MB) -> SHA eşleşti (17.89s)
        - T2 (norange tek akış) -> SHA eşleşti, bozulma yok (1.18s)
        - T3 (unknown-length) -> SHA eşleşti, boyut doğru (0.62s)
        - T4 (ratelimit & AIMD 429/503) -> bağlantı azaldı, bitti, SHA eşleşti (2.21s)
        - T5 (flaky kopmalar) -> otomatik kurtarıldı, bitti, SHA eşleşti (4.61s)
        - T6 (slow iş çalma) -> yavaş parça bölündü, makul sürede bitti (0.60s)
        - T7 (etag-change) -> If-Range uyuşmazlığında `.fileChanged` hatası fırlatıldı (0.07s)
        - T8 (redirect) -> 302 zinciri izlendi, son URL kaydedildi, SHA eşleşti (0.37s)
        - T9 (gzip-force) -> identity gönderildiği için ofsetler bozulmadı, SHA eşleşti (0.37s)
        - T10 (disposition & çakışma) -> "Türkçe dosya.zip" ve "Türkçe dosya (1).zip" üretildi (0.13s)
        - T11 (pause -> resume bayt doğrulaması) -> sunucu tarafında indirilen baytlar mükerrer indirilmedi (2.45s)
        - T12 (çökme & resume simülasyonu) -> SHA eşleşti (2.81s)
        - T13 (loopback performans):
          - Debug: 92.92 MB/s
          - Release (`-c release`, Apple Silicon loopback): **2365.53 MB/s** (256 MB in 0.108s, hedef: ≥ 300 MB/s, 7.8 kat aşıldı).
      - `EngineTests` (10 test): AIMD, boundary trimming, retry reallocation, dosya adı ayrıştırma, RFC5987, dosya adı temizleme, ilk bölümleme, max attempts, açık uçlu parça, iş çalma hepsi başarılı.
      - `TestHTTPServerTests` (10 test): 10 profilin tümü başarılı.
      - `KodizBridgeProtocolTests` (2 test): mesaj serileştirme ve çerçeveleme başarılı.
    - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path Tools/kdm-cli --scratch-path /tmp/kodiz-cli-build` -> BUILD SUCCESS.
  - **Sırada:** AŞAMA 3 — Kalıcılık ve Uygulama Katmanı (A1–A5).

- [x] **AŞAMA 3 — Kalıcılık ve Uygulama Katmanı (A1–A5)**
  - **Yapılanlar:**
    - **A1 (KodizStore & Checkpoint):** `KodizDatabase`'e `DownloadCheckpointSink` protokolü uygulandı; `checkpoint(id:segments:downloadedBytes:)` ile parça durumları ve indirilen baytlar SQLite'a atomik olarak yazılıyor. `fetchEngineSegments`, `deleteDownload` (cascade segment silme), `updateDownloadStatus`, `updateDownloadDetails` repository metodları eklendi.
    - **Keychain Çerez Yönetimi:** `KeychainCookieStore` yazıldı (`kSecClassGenericPassword`, `dev.kodiz.DownloadManager.cookies`). Çerezler veritabanına düz metin yazılmıyor; indirme başına Keychain'de saklanıp indirme tamamlandığında veya silindiğinde temizleniyor.
    - **A2 & DownloadManager:** `DownloadManager` (`@Observable @MainActor`) yazıldı.
      - Motor örneklerini (`engines`), eşzamanlı indirme kuyruğunu (varsayılan 4) ve durum makinesini (`queued`, `downloading`, `paused`, `waitingNetwork`, `completed`, `failed`) yönetiyor.
      - Açılışta SQLite'tan yükleme yapıyor; yarıda kalan indirmeler otomatik olarak `.paused` durumuna alınıyor.
      - `NetworkObserver` (`NWPathMonitor`) ile ağ kesildiğinde indirmeler `.waitingNetwork` durumuna alınıp ağ gelince otomatik sürdürülüyor.
      - Aktif indirme varken `SleepBlocker` (IOPMAssertion) ile Mac'in uyuması engelleniyor; indirmeler bitince serbest bırakılıyor.
      - Bitişte `FileMetadata` (`applyQuarantine`, `applyWhereFroms`, `notifyDockDownloadsBounce`) tetikleniyor.
    - **A2 (Arayüz Temizliği):** `KodizApp.swift` ve `MainWindowView.swift` içindeki tüm sahte/mock veriler kaldırıldı. Toolbar ve sağ tık menüsündeki tüm eylemler (`Duraklat`, `Sürdür`, `Sil`, `Dosyayla Sil`, `Finder'da Göster`, `Aç`, `URL'yi Kopyala`) `DownloadManager`'a bağlandı. Detay penceresi ve IDM tarzı parça tuvali (`SegmentCanvasView`) gerçek zamanlı verilere bağlandı.
    - **A4 (LSUIElement & Yaşam Döngüsü):** `Info.plist`'e `LSUIElement = YES` eklendi. `AppDelegate` ilk açılışta ana pencereyi açıp `hasLaunchedBefore` bayrağını kaydediyor; sonraki açılışlarda menü çubuğunda kalıyor (`.accessory`). Pencere açılınca `.regular`, kapanınca `.accessory` politikası uygulanıyor.
  - **Çalıştırılan Testler & Kanıt:**
    - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/KodizKit --filter "StoreTests" --scratch-path /tmp/kodiz-kk-build`
      - Sonuç: 3/3 test başarılı (testCheckpointSinkAndSegmentFetching, testDatabaseInitializationAndMigrations, testSaveAndFetchDownload).
    - `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project KodizDownloadManager.xcodeproj -scheme "Kodiz Download Manager" -derivedDataPath /tmp/kodiz-dd build CODE_SIGNING_ALLOWED=NO`
      - Sonuç: **BUILD SUCCEEDED** (Kodiz Download Manager.app, NativeHost, KodizSafari.appex başarıyla derlendi ve bağlandı).
  - **Doğrulama Durumu:**
    - Derleme: DOĞRULANDI (BUILD SUCCEEDED).
    - UI Görsel / Ekran Görüntüsü: DOĞRULANMADI — neden: CLI/terminal oturumunda grafik ekran çıktısı ve pencere yöneticisi doğrudan yakalanamıyor.
  - **Elle Duman Testi Adımları:**
    1. Uygulamayı başlat: `open /tmp/kodiz-dd/Build/Products/Debug/"Kodiz Download Manager.app"`
    2. Menü çubuğundaki Kodiz simgesine tıkla -> Popover açılır, aktif indirme olmadığını gösterir.
    3. "+ URL Ekle" veya "Ana Pencere"ye tıkla -> Ana pencere açılır, Dock simgesi belirir.
    4. "URL Ekle" düğmesine bas -> Bir test URL'si (ör. `http://127.0.0.1:<port>/range?size=10485760`) gir ve "Probe Et"e bas.
    5. Boyut ve sürdürme desteği bilgisi geldikten sonra "Hemen Başlat"a bas -> İndirme listeye eklenir, hız ve ilerleme çubuğu canlı güncellenir.
    6. İndirmeye sağ tıkla -> "Duraklat" seç -> Durum "Paused" olur, hız 0'a iner.
    7. Tekrar sağ tıkla -> "Sürdür" seç -> İndirme kaldığı bayttan devam eder ve tamamlanır.
    8. Sağ tıkla -> "Finder'da Göster" seç -> İndirilen dosya Finder'da vurgulanır.
    9. Ana pencereyi kapat -> Dock simgesi kaybolur, uygulama menü çubuğunda çalışmaya devam eder.
  - **Sırada:** AŞAMA 4 — Köprü ve Native Host (K1–K6, A3).

- [x] **AŞAMA 4 — Köprü ve Native Host (K1–K6, A3)**
  - **Yapılanlar:**
    - **Ortak Soket Yolu (K2):** `BridgeSocketPath.resolveSocketPath()` tek bir merkezi fonksiyon olarak `KodizBridgeProtocol`'e eklendi. App Group konteyneri çözülürse `<group>/bridge.sock`, aksi halde `~/Library/Application Support/Kodiz Download Manager/bridge.sock` döndürülüyor. `sun_path` 104 bayt sınırı doğrulanıyor. `AppGroupPaths` da buna uyarlandı.
    - **FD Yaşam Döngüsü & Async Yanıt (K1):** `BridgeServer.swift` tamamen asenkron `handleClientAsync(fd:)` mimarisine geçirildi. Dosya tanımlayıcısı yanıt tam olarak yazılana kadar açık tutuluyor (`defer { close(fd) }` yalnızca async döngü bittiğinde çalışıyor). Kapanmış veya devredilmiş FD'ye yazma riski tamamen ortadan kaldırıldı.
    - **Kısmi Yazma / Soket Güvenliği (K6):** `UnixSocketClient` ve `BridgeServer` düşük seviyeli `send`/`recv` döngüleriyle kısmi yazmaları tam boyuta ulaşana kadar sürüyor. `SO_NOSIGPIPE`, `SO_RCVTIMEO` ve `SO_SNDTIMEO` (10 saniye) eklendi. Tek bağlantıda çoklu istek desteği eklendi.
    - **Karşı Taraf Doğrulaması (K3):** `MacPeerValidator` yazıldı. `getsockopt(LOCAL_PEERTOKEN)` ile arayan sürecin audit token'ı alınıyor; `SecCodeCopyGuestWithAttributes` ve `SecCodeCheckValidity` ile `dev.kodiz.NativeHost` veya `dev.kodiz.DownloadManager.SafariExtension` yetkili bundle kimlikleri kontrol ediliyor. Testler ve yerel imzasız çalıştırma için `AllowAllPeerValidator` ve `KODIZ_ALLOW_UNSIGNED_BRIDGE=1` kaçış yolu sağlandı (Release derlemesinde bypass engelleniyor).
    - **Girdi Güvenliği:** HTTP/HTTPS şema zorunluluğu, 4096 bayt URL sınırı, CRLF injection engeli ve mesaj başına 1 MB sınırı eklendi.
    - **A3 & K1 Birlikte Çözümü:** `AppDelegate.handleBridgeMessage` içinde `download.add` isteği geldiğinde dosya önce SQLite veritabanına kaydedilip kuyruğa ekleniyor; ardından eklentiye gerçek `downloadId` ve `ok: true` yanıtı dönülüyor. Hata durumunda `ok: false, reason: ...` dönülerek tarayıcının indirmeyi iptal etmesi engelleniyor.
    - **NMH Uygulama Başlatma (K4):** `NativeMessagingHost.swift` stdin/stdout çerçevelemesini düşük seviyeli okuma/yazma döngüleriyle yapıyor. Soket bulunamadığında (uygulama kapalıyken) `NSWorkspace.shared.openApplication(at:configuration:)` ile uygulamayı arka planda (`activates = false`, `--background`) başlatıyor ve soketi 8 saniyeye kadar yokluyor. `hello` mesajı için uygulama gereksiz yere başlatılmıyor.
    - **Manifest Kurucu (NativeHostInstaller):** Chrome, Canary, Chromium, Brave, Edge, Opera, Vivaldi ve Firefox için JSON manifestleri `~/Library/Application Support/.../NativeMessagingHosts` klasörlerine yazan `NativeHostInstaller` uygulandı. Opera ve Vivaldi hem kendi yollarına hem Chrome yoluna yazılarak belgelendi.
    - **Sabit Chromium Kimliği:** RSA-2048 anahtar çifti üretildi (`/tmp/kodiz-keys/kodiz_extension_private.pem`). Base64 DER açık anahtarı manifest'e ve eklenti yapılandırmasına eklendi. Türetilen Extension ID: `clcoapdgcnijgajpkdplenikocmfpdfg`. Özel anahtar repoya konulmadı (`.gitignore` koruması altında).
    - **Safari Appex (K5):** `SafariExtension.entitlements` dosyasına `com.apple.security.app-sandbox = true` ve `application-groups` eklendi. `SafariWebExtensionHandler.swift` gelen mesajı Unix soketine iletiyor, gerekirse uygulamayı arka planda açıyor ve gerçek yanıtı Safari'ye döndürüyor.
  - **Çalıştırılan Testler & Kanıt:**
    - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/KodizKit --filter "BridgeProtocolTests" --scratch-path /tmp/kodiz-kk-build`
      - Sonuç: 7/7 test başarılı (testBridgeMessageSerialization, testMessageFraming, testConcurrent50Requests, testDelayedDelegateResponse, testMalformedMessageHandling, testLargeMessageRejection, testNativeHostInstallerManifestGeneration).
    - `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project KodizDownloadManager.xcodeproj -scheme "Kodiz Download Manager" -derivedDataPath /tmp/kodiz-dd build CODE_SIGNING_ALLOWED=NO`
      - Sonuç: **BUILD SUCCEEDED** (Kodiz Download Manager.app, NativeHost ve KodizSafari.appex).
  - **Doğrulama Durumu:**
    - Köprü soket iletişimi ve 50 eşzamanlı istek: DOĞRULANDI (Birim/entegrasyon testleriyle).
    - NMH manifest yazımı: DOĞRULANDI (Birim testleriyle).
    - Safari appex derlemesi: DOĞRULANDI (BUILD SUCCEEDED).
    - Safari'de gerçek tarayıcı çalıştırması: DOĞRULANMADI — neden: Apple Developer hesabı ve imzalı Appex kimliği gerektiriyor.
    - Opera / Vivaldi NMH yolları: DOĞRULANMADI — neden: Belirtilen tarayıcılar test ortamında kurulu değil; her iki tarayıcı için hem kendi hem de Chrome manifest yollarına yazıldı.
  - **Sırada:** AŞAMA 5 — Eklenti (X1–X8).

- [x] **AŞAMA 5 — Eklenti (X1–X8)**
  - **Yapılanlar:**
    - **Cross-Browser Standartlaşma:** Tüm eklenti kodunda `chrome.*` yerine WXT'nin `browser.*` nesnesi kullanıldı (Promise tabanlı, Chromium, Firefox ve Safari uyumlu).
    - **X1 (Safari Uyumluluğu):** Safari'de `browser.downloads` bulunmadığı için `background.ts`'te `browser.downloads.onCreated` koşullu olarak bağlandı. Safari için `content.ts` içinde indirilebilir uzantılara giden veya `download` özniteliği taşıyan `<a>` tıklamalarını yakalayıp background'a (`intercept_click`) bildiren ve uygulama reddederse normal indirmeyi devam ettiren mekanizma kuruldu.
    - **X2 (Dosya Türü & Boyut Filtresi):** `filter.ts` saf fonksiyonları yazıldı. Yapılandırma `getConfig` Native Messaging mesajı ile uygulamadan alınıp `browser.storage.local`'da (`kodiz_config`) önbellekleniyor. İndirilebilir uzantılar (video, ses, arşiv, yürütülebilir dosyalar), hariç tutulan uzantılar (pdf, png, jpg vb.), hariç alan adları ve 1 MB altı indirmelerin filtrelenmesi uygulandı.
    - **X3 (Option / ⌥ ile Atlama):** `content.ts` tıklamalarda `e.altKey` durumunu yakalayıp background'a (`bypass_download`) bildiriyor. Background 5 saniye boyunca bu URL için yakalamayı devre dışı bırakıyor.
    - **X4 (Aç/Kapa Anahtarı & Popup):** Popup içindeki `#toggle-intercept` anahtarı `storage.local` üzerinden `config.enabled` değerine bağlandı. Popup açıldığında Kodiz yerel uygulamasıyla bağlantı durumu kontrol edilip "Bağlı" / "Bağlantı Yok" rozeti gösteriliyor.
    - **X5 (Medya Algılama & Debounce):** `content.ts` içine 500 ms debounce'lu `MutationObserver` ve `PerformanceObserver` eklendi; sayfa içindeki `.m3u8`, `.mpd`, `.ism` akışları ve `<video>/<audio>` kaynakları tekilleştirilerek background'a gönderiliyor. Background sekme bazlı medya listesini tutuyor, araç çubuğu rozetinde sayıyı gösteriyor, sekme kapanınca/yenilenince temizliyor. Popup içinde tespit edilen medyalar listelenip tek tıkla "İndir" düğmesiyle uygulamaya aktarılabiliyor.
    - **X6 (Gizli Pencere Kontrolü):** `item.incognito` indirmeleri `interceptIncognito` ayarı kapalıyken tarayıcıya bırakılıyor (varsayılan kapalı).
    - **X7 (Zaman Aşımı & Yarış Koşulu Çözümü):** 10 saniyelik zaman aşımı ve geç gelen köprü yanıtlarının çakışmasını engellemek için tek seferlik `settled` bayrağı eklendi. Zaman aşımına uğramış bir indirme için `cancel` çağrılması engellendi.
    - **X8 (totalBytes & Özel Şemalar):** `fileSize` yerine `totalBytes` kullanıldı; `blob:`, `data:` ve `file:` şemaları filtrelenerek doğrudan tarayıcıya bırakıldı.
    - **Sabit Chrome Kimliği:** `wxt.config.ts` içinde Chrome hedefi için RSA-2048 DER base64 anahtarı `manifest.key` olarak eklendi.
    - **Testler:** `filter.ts` ve `media.ts` saf fonksiyonları Vitest ile birim testlerine tabi tutuldu.
  - **Çalıştırılan Testler & Kanıt:**
    - `npm test` (Extension dizininde):
      - Sonuç: 2 test dosyası, 17/17 test başarılı (`filter.test.ts`: 15 test, `media.test.ts`: 2 test).
    - `npm run compile` (`tsc --noEmit`):
      - Sonuç: Hatasız geçti (Exit code 0).
    - `npx wxt build -b chrome`:
      - Sonuç: Başarılı (manifest.json, background.js, content.js, popup.html üretildi, manifest'te `key` doğrulandı).
    - `npx wxt build -b firefox`:
      - Sonuç: Başarılı (firefox-mv2 üretildi).
    - `npx wxt build -b safari`:
      - Sonuç: Başarılı (safari-mv2 üretildi).
  - **Doğrulama Durumu:**
    - Birim testleri ve TypeScript derlemesi: DOĞRULANDI (17/17 Vitest, tsc 0 hata).
    - WXT build (Chrome, Firefox, Safari): DOĞRULANDI.
    - Gerçek tarayıcıda canlı tıklama/indirme yakalama testi: DOĞRULANMADI — neden: Başlıksız terminal ortamında tarayıcı UI oturumu açılamıyor.
  - **Sırada:** AŞAMA 6 — Betikler, CI ve Belgeler (B1–B4).

- [ ] **AŞAMA 6 — Betikler, CI ve Belgeler (B1–B4)**


