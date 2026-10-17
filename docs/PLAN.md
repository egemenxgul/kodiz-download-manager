# Kodiz Download Manager — Proje Planı

**Sürüm:** 0.1 (taslak) · **Tarih:** 17 Ekim 2026 · **Durum:** §17'deki açık sorular yanıtlanınca kesinleşecek

---

## 0. Özet

Kodiz Download Manager (KDM), macOS için yerel (Swift/SwiftUI) ve açık kaynaklı bir indirme yöneticisidir. Menü çubuğunda yaşar. Çok bağlantılı ve dinamik parçalamalı bir HTTP motoru, tek kaynaklı tarayıcı eklentisi, yt-dlp tabanlı video indirme ve IDM tarzı ayrıntılı bir arayüz sunar. Tek bir `.app` olarak dağıtılır. Native messaging host, Safari eklentisi, yt-dlp, ffmpeg ve JS runtime paketin içindedir.

### Temel kararlar

| Konu | Karar | Gerekçe |
|---|---|---|
| Dil / UI | Swift 6 + SwiftUI, gerektiği yerde AppKit | Yerel görünüm, düşük kaynak tüketimi, macOS 26+ SDK ile Liquid Glass görünümü kendiliğinden gelir |
| Minimum macOS | **14 Sonoma** | `@Observable`, `SMAppService`, `MenuBarExtra`, özelleştirilebilir `Table`, `WKWebsiteDataStore(forIdentifier:)` |
| Mimari | **Universal 2** (arm64 + x86_64), M serisi öncelikli | Intel desteğinin maliyeti düşük. Testler önce Apple Silicon'da yapılır |
| Dağıtım | App Store dışı: **Developer ID + notarization**, DMG + Sparkle | App Store sandbox'ı yt-dlp/ffmpeg çalıştırmayı ve tarayıcı manifest kurulumunu engeller |
| Sandbox | Ana uygulama sandbox'sız + Hardened Runtime. Safari eklentisi (appex) sandbox'lı | Teknik zorunluluk |
| Ağ | `URLSession`, **her bağlantı için ayrı URLSession** | HTTP/2 multiplexing'i aşıp gerçekten ayrı TCP bağlantıları açmak için (§4.4) |
| Kalıcılık | SQLite + **GRDB.swift** (WAL) | Sık ilerleme yazımı, çökmeye dayanıklılık, şema göçleri |
| Tarayıcı eklentisi | Tek kaynak TypeScript, **WXT** framework, Manifest V3 | Chrome/Brave/Opera/Edge/Vivaldi/Firefox/Safari çıktıları tek koddan üretilir |
| Video | yt-dlp (onedir sürümü) + ffmpeg (LGPL, kendi derlememiz) + QuickJS-ng | YouTube artık JS runtime gerektiriyor (§8.1) |
| Güncelleme | Sparkle 2 (uygulama), dahili güncelleyici (yt-dlp) | Standart ve güvenli (EdDSA imzalı) |
| Proje dosyası | **XcodeGen** (`project.yml`) | Açık kaynakta `.pbxproj` çakışmalarını önler |
| Lisans | **MIT** (öneri) + üçüncü taraf bildirimleri | §16 |

---

## 1. Hedefler ve kapsam

### 1.1 v1.0 hedefleri
1. macOS 14+ üzerinde, Apple Silicon ve Intel'de sorunsuz çalışan, imzalı ve notarize edilmiş tek `.app`.
2. Çok parçalı, sürdürülebilir, çökmeye dayanıklı HTTP/HTTPS indirme motoru.
3. Safari, Chrome, Brave, Opera, Edge, Firefox (Vivaldi en iyi çaba) entegrasyonu ve adım adım kurulum sihirbazı.
4. Uygulama kapalıyken eklentinin onu başlatması. Başlatamazsa indirme tarayıcıda devam eder.
5. Video ve akış indirme (yt-dlp + ffmpeg). YouTube dahil tek tıkla indirme.
6. Menü çubuğu uygulaması, ana pencere, IDM tarzı dosya penceresi, bildirimler.
7. Türkçe ve İngilizce arayüz.

### 1.2 v1.0 kapsamı dışında
- FTP/SFTP, BitTorrent/magnet, Metalink (v1.1+ değerlendirilir)
- Windows/Linux, iOS, Mac App Store sürümü
- **DRM korumalı içerik** (Netflix, Disney+, Spotify, Widevine/FairPlay). Teknik ve hukuki nedenlerle hiçbir sürümde yapılmayacak.

### 1.3 Ölçülebilir başarı ölçütleri
| Ölçüt | Hedef |
|---|---|
| Verim | 1 Gbps hatta 8 bağlantıyla hattı doyurmak; M1'de CPU < %15 |
| Bellek | 10 aktif indirmede < 200 MB |
| Dayanıklılık | `kill -9` sonrası en fazla ~2 sn'lik veri yeniden iner, dosya bozulması 0 |
| Tarayıcı → Kodiz devri | Uygulama açıkken < 300 ms, kapalıyken < 3 sn |
| Açılış | Oturum açılışında menü çubuğuna < 1 sn |
| Arayüz | 5.000 satırlık geçmişte akıcı kaydırma; ilerleme güncellemesi 4 Hz |

---

## 2. Temel kullanıcı senaryoları

| # | Senaryo | Beklenen davranış |
|---|---|---|
| S1 | İlk kurulum | DMG → Uygulamalar → açılış sihirbazı → izinler → oturum açılışında başlatma → tarayıcılar tek tek kurulur ve canlı doğrulanır |
| S2 | Chrome'da bir `.dmg` bağlantısına tıklama | Eklenti indirmeyi duraklatır, Kodiz kabul edince tarayıcıdaki indirmeyi iptal edip listeden siler. Kodiz 8 bağlantıyla indirir |
| S3 | Uygulama kapalıyken S2 | Native host uygulamayı arka planda başlatır (pencere ve Dock simgesi yok) ve indirmeyi teslim eder. Başaramazsa tarayıcı devam eder |
| S4 | URL yapıştırma | ⌘N veya menü çubuğu → URL eklenir (pano otomatik okunur) → boyut, ad ve Range desteği önceden gösterilir |
| S5 | Duraklat / Mac'i yeniden başlat / sürdür | Parça durumu diskten okunur, kalan baytlardan devam edilir |
| S6 | YouTube'da "Bu videoyu indir" | Varsayılan ön ayarla (≤1080p MP4) tek tıkla iner. Sağ tık veya ⌥ tık format seçiciyi açar |
| S7 | Bir sitede HLS (.m3u8) yayını | Eklenti akışı algılar, rozet sayısı artar, popup'tan indirilir. Çerez, Referer ve UA aktarılır |
| S8 | İmzalı bağlantının süresi doldu (403) | "Bağlantıyı yenile" ile yeni URL verilir. Boyut ve ETag tutarsa ilerleme korunur |
| S9 | Wi-Fi koptu veya Mac uykuya geçti | İndirmeler "Ağ bekleniyor" durumuna geçer, bağlantı gelince kendiliğinden sürer |

---

## 3. Mimari

### 3.1 Paket yapısı ve süreçler

```
Kodiz Download Manager.app
└── Contents
    ├── MacOS/Kodiz Download Manager      ← ana süreç (LSUIElement, sandbox'sız, hardened)
    ├── Helpers/kodiz-nmh                 ← native messaging host (CLI, UI yok)
    ├── PlugIns/KodizSafari.appex         ← Safari Web Extension (sandbox'lı)
    ├── Resources/Tools/
    │   ├── yt-dlp/                       ← yt-dlp_macos onedir (kendi imzamızla)
    │   ├── ffmpeg, ffprobe               ← LGPL universal derleme
    │   └── qjs                           ← QuickJS-ng
    ├── Resources/BrowserExtensions/
    │   ├── chromium/                     ← paketlenmemiş MV3 eklentisi
    │   └── kodiz-firefox.xpi             ← AMO "unlisted" imzalı
    └── Library/…                         ← (gerekirse) LaunchAgent plist
```

```
 Chrome / Brave / Opera / Edge ─┐  stdio (native messaging, uzunluk önekli JSON)
 Firefox ───────────────────────┴──► kodiz-nmh ─────┐
                                                    ├──► Unix soket (App Group konteyneri) ──► Ana süreç
 Safari ──► KodizSafari.appex (SafariWebExtensionHandler) ┘                                     │
                                                                                                 ├─ UI (SwiftUI/AppKit)
                                                                                                 ├─ DownloadManager (actor)
                                                                                                 ├─ Engine (HTTP motoru)
                                                                                                 ├─ Media (yt-dlp/ffmpeg)
                                                                                                 └─ Store (GRDB)
```

**Neden tek ana süreç?** Uygulama zaten oturum açılışında başlayıp sürekli çalışıyor. Motoru ve arayüzü aynı süreçte, actor'lerle ayrılmış biçimde tutmak hem daha basit hem daha hızlı. Ağ ve disk işleri ana iş parçacığına (main thread) hiç dokunmaz.

### 3.2 Modüller (`KodizKit` Swift Package)

| Modül | Sorumluluk | Bağımlılık |
|---|---|---|
| `KodizEngine` | Probe, parça planlayıcı, bağlantı işçileri, FileWriter, hız sınırlayıcı, yeniden deneme, AIMD | Yalnızca Foundation. UI'dan bağımsız, CLI ile test edilebilir |
| `KodizStore` | GRDB modelleri, göçler, depolar | GRDB |
| `KodizBridgeProtocol` | Uygulama, nmh ve appex'in paylaştığı sürümlü `Codable` mesajlar ve çerçeveleme | Foundation |
| `KodizMedia` | yt-dlp çalıştırıcı, ilerleme ayrıştırıcı, format modeli, araç güncelleyici, Netscape çerez dosyası | KodizEngine |
| `KodizSystem` | Oturum açılış öğesi, uyku engeli, ağ izleyici, karantina/WhereFroms xattr, Finder ilerlemesi, bildirimler, App Group yolları | AppKit, IOKit, Network |
| `kdm-cli` (geliştirme aracı) | `kdm-cli get <url> -c 8`: motoru arayüz olmadan test eder | KodizEngine |

### 3.3 Repo yapısı

```
kodiz-download-manager/
├── project.yml                  # XcodeGen
├── App/                         # macOS uygulama hedefi (SwiftUI görünümleri, AppDelegate, MenuBar)
├── NativeHost/                  # kodiz-nmh hedefi
├── SafariExtension/             # appex hedefi (SafariWebExtensionHandler.swift)
├── Packages/KodizKit/           # Sources/{KodizEngine,KodizStore,KodizBridgeProtocol,KodizMedia,KodizSystem}, Tests/
├── Extension/                   # WXT TypeScript projesi (chromium, firefox, safari çıktıları)
├── Tools/
│   ├── TestServer/              # hata enjekte eden yerel HTTP sunucusu (SwiftNIO)
│   ├── kdm-cli/
│   └── versions.json            # sabitlenmiş yt-dlp / ffmpeg / qjs sürümleri ve SHA-256'ları
├── Scripts/                     # build-ffmpeg.sh, fetch-tools.sh, sign.sh, notarize.sh, make-dmg.sh
├── docs/                        # PLAN.md, spikes/, mimari notlar, kullanıcı rehberi
└── .github/workflows/           # ci.yml, tools.yml, release.yml
```

---

## 4. İndirme motoru

### 4.1 Akış

1. **Probe:** `GET` ve `Range: bytes=0-0`, `Accept-Encoding: identity` gönderilir. HEAD'e güvenilmez, birçok sunucu HEAD'i yanlış yanıtlar.
   - `206` ve `Content-Range: bytes 0-0/TOPLAM`: Range destekleniyor, boyut biliniyor.
   - `200`: Range yok. **Bu yanıt boşa atılmaz**, doğrudan tek akış olarak indirmeye devam edilir.
   - Kaydedilenler: son URL (yönlendirmeler sonrası), `ETag`, `Last-Modified`, `Content-Type`, `Content-Disposition`.
2. **Dosya adı** belirlenir (§4.5).
3. **Disk alanı kontrolü** (`volumeAvailableCapacityForImportantUsage`) yapılır ve dosya önceden ayrılır.
4. **Parça planı** çıkarılır (§4.2).
5. **İşçiler** başlar, ilerleme düzenli olarak diske işlenir.
6. **Bitiş:** boyut doğrulanır, varsa checksum kontrol edilir, `fsync` → `.kodizpart` atomik olarak gerçek ada çevrilir → xattr'lar yazılır → bildirim gösterilir → Dock'taki İndirilenler yığını zıplatılır.

### 4.2 Dinamik parçalama (IDM tarzının geliştirilmiş hâli)

- **Başlangıç:** Dosya N eşit parçaya bölünür. En küçük parça 1 MiB'dir; küçük dosyalarda `N = min(N, ⌈boyut / 1 MiB⌉)`.
- **İş çalma (work stealing):** İşini bitiren bağlantı, kalan baytı en büyük parçayı (2 × en küçük parçadan büyükse) 64 KiB'ye hizalı ortasından böler ve ikinci yarıyı alır. Eski işçinin bitiş sınırı actor içinde atomik olarak küçültülür. İşçi yeni sınıra ulaşınca isteğini kapatır. Böylece IDM'deki "son parçayı tek bağlantı bekler" sorunu ortadan kalkar.
- **Yavaş bağlantı değişimi:** Her işçinin hızı EWMA ile izlenir. 10 sn boyunca medyanın %25'inin altında kalan ve önünde 4 MiB'den fazla iş olan işçinin kalan kısmı bölünür ya da işçi yeni bir TCP bağlantısıyla (başka bir CDN ucuna düşebilir) yeniden başlatılır.
- **Canlı değişiklik:** Detay penceresinde bağlantı sayısı değiştirilince parçalar hemen bölünür veya işçiler emekliye ayrılır.

### 4.3 Bağlantı sayısı: sabit veya otomatik

- Ayar 1–16 arası, **varsayılan 8**. Ek olarak **"Otomatik"** modu vardır.
- **Otomatik (AIMD):** 4 bağlantıyla başlanır. Toplam verim %5'ten fazla arttığı sürece her 3 sn'de +1 eklenir. 429/503, bağlantı reddi veya sıfırlama patlamalarında sayı **yarıya** iner, `Retry-After` dikkate alınır ve 30 sn boyunca artırma yapılmaz.
- **Host hafızası:** `host_profiles` tablosu her host için öğrenilen güvenli bağlantı sayısını ve Range desteğini tutar. Sonraki indirme bu değerle başlar.
- **Host nezaketi:** Tüm indirmeler toplamında aynı hosta en fazla 16 bağlantı açılır (ayarlanabilir).

### 4.4 Gerçek paralellik: HTTP/2 tuzağı

`URLSession`, aynı hosta giden istekleri HTTP/2'de **tek TCP bağlantısında** çoklar. Bu durumda "8 bağlantı" aslında tek bağlantı olur ve hızlanma kaybolur. Çözüm olarak her işçi kendi `URLSession`'ına sahiptir (ephemeral yapılandırma, önbellek yok, çerez deposu yok). Her oturumun bağlantı havuzu ayrı olduğu için gerçekten ayrı TCP bağlantıları açılır. **Faz 0 spike'ı** bunu Cloudflare ve GitHub CDN üzerinde ölçecek. Yetersiz çıkarsa yedek plan SwiftNIO/AsyncHTTPClient ile HTTP/1.1 zorlamaktır.

### 4.5 İstek ayrıntıları

- **Başlıklar:** User-Agent (tarayıcıdan gelen ya da varsayılan Safari UA), Referer ve Cookie elle eklenir. Oturumun çerez deposu kapalıdır (`httpCookieStorage = nil`, `httpShouldSetCookies = false`).
- **`Accept-Encoding: identity` zorunludur.** Aksi hâlde URLSession gzip ister ve içeriği kendisi açar. O zaman bayt aralıkları dosya ofsetleriyle eşleşmez ve dosya bozulur.
- **Sürdürmede doğrulama:** `If-Range: <ETag | Last-Modified>` gönderilir. Sunucu `206` yerine `200` dönerse dosya değişmiştir: "Dosya sunucuda değişmiş. Baştan başlatılsın mı?"
- **Yönlendirmeler:** Takip edilir ve son URL saklanır. Sürdürmede önce son URL denenir; 403/404/410 alınırsa orijinal URL'ye dönülür.
- **Kimlik doğrulama:** Basic/Digest `URLAuthenticationChallenge` ile yapılır, kimlik bilgileri Keychain'de tutulur.
- **Proxy:** Varsayılan sistem proxy'si. Özel HTTP/HTTPS/SOCKS5 proxy `connectionProxyDictionary` ile verilir.
- **Zaman aşımları:** Bağlanma 15 sn, boşta okuma 30 sn (ayarlanabilir).
- **Dosya adı:** Öncelik sırası RFC 6266 ve RFC 5987 `Content-Disposition` (`filename*=UTF-8''…`), ardından yüzde kodlaması çözülmüş URL yolu, en son MIME türünden `UTType` ile uzantı.
- **Ad temizleme:** `/` ve `:` değiştirilir, kontrol karakterleri atılır, NFC normalizasyonu yapılır, uzantı korunarak en fazla 255 bayta kısaltılır. Çakışmada `dosya (1).zip` / üzerine yaz / sor seçenekleri sunulur.

### 4.6 Hata yönetimi

| Sınıf | Örnekler | Davranış |
|---|---|---|
| Geçici | Zaman aşımı, bağlantı sıfırlama, DNS geçici hatası, 5xx, 408 | Jitter'lı üstel geri çekilme (1, 2, 4 … en fazla 60 sn). Parça başına en fazla 10 deneme |
| Sınırlama | 429, 503 | `Retry-After` dikkate alınır ve bağlantı sayısı yarıya iner (AIMD) |
| Bağlantı geçersiz | 404, 410 | "Bağlantı geçersiz. Yenilemek ister misiniz?" |
| Yetki | 401, 403 | "Çerez veya yetki sorunu" → Bağlantıyı yenile / tarayıcıda tekrar yakala |
| Range hatası | 416 | Yeniden probe edilir |
| Disk | ENOSPC, EACCES | O birimdeki indirmeler duraklar, bildirim gösterilir / yeni klasör sorulur |
| Ağ yok | `NWPathMonitor` unsatisfied | "Ağ bekleniyor" durumuna geçilir, bağlantı gelince otomatik devam edilir |
| Uyku | — | Aktif indirme varken boşta uykuyu engelleme (IOPM assertion, ayarlanabilir). Uyanınca yeniden bağlanılır |

### 4.7 Disk G/Ç

- **Geçici dosya:** `<hedef klasör>/<ad>.kodizpart`. Aynı birimde olduğu için ad değiştirme atomiktir. Hedef farklı birimdeyse bitişte taşınır.
- **Finder'da ilerleme:** `Progress` nesnesi `fileURL` ile `publish()` edilir. Finder, Safari'deki gibi dosya simgesinin üstünde ilerleme çubuğu gösterir.
- **Ön ayırma:** `ftruncate` (APFS seyrek dosya) ve isteğe bağlı `fcntl(F_PREALLOCATE)` kullanılır. Böylece indirmenin ortasında disk dolmaz.
- **Yazma:** Her işçi havuzdan alınan 1 MiB'lik tamponlarda veri biriktirir. Dosya başına tek bir seri G/Ç kuyruğu `pwrite` ile ofsete yazar.
- **Checkpoint:** Her 2 sn'de veya 16 MiB'de bir önce `fsync(fd)`, **sonra** parça ilerlemesi tek transaction ile veritabanına yazılır. Böylece veritabanı diskte olmayan baytları asla "indirildi" saymaz.
- **Bitişte xattr'lar:**
  - `com.apple.quarantine` (ajan adı "Kodiz Download Manager"): indirilen uygulamaları Gatekeeper denetler. Sorumlu bir indirme yöneticisi bunu atlamamalıdır.
  - `com.apple.metadata:kMDItemWhereFroms` ([URL, Referer]): Finder'daki "Nereden" bilgisi.
  - `com.apple.DownloadFileFinished` dağıtık bildirimi: Dock'taki İndirilenler yığınının zıplaması.
- **4 GB üstü dosyalar:** Her yerde 64 bit ofset kullanılır. 10 GB+ dosyalarla test edilir.

### 4.8 Hız sınırı, kuyruk ve zamanlama

- **Token bucket:** Genel ve indirme başına sınır. Kova boşalınca işçinin data task'ı `suspend()` edilir, TCP akış kontrolü göndericiyi kendiliğinden yavaşlatır.
- **Kuyruklar:** Ana kuyruk ve kullanıcı kuyrukları. Eşzamanlı indirme sayısı varsayılan 4'tür. Belirli saatte başlat/durdur seçenekleri vardır.
- **Kuyruk bitince:** hiçbir şey yapma / uyku. "Bilgisayarı kapat" Apple Events izni gerektirir, v1.1'e bırakıldı.
- **Seçenekler:** Pilde duraklat, pahalı ağda (hotspot) veya Düşük Veri Modu'nda duraklat.

### 4.9 Ek motor özellikleri

- **Bağlantıyı yenile:** Kullanıcı yeni URL yapıştırır ya da eklenti aynı ad ve boyutta bir dosyayı tekrar yakaladığında "Bu, duraklatılmış X'in devamı mı?" diye sorar. Boyut ve ETag tutarsa parçalar korunur.
- **Toplu ekleme:** Çoklu URL yapıştırma ve `resim[001-120].jpg` desenleri.
- **Pano izleme** (varsayılan kapalı): Yakalanacak türde bir URL kopyalanınca "İndirilsin mi?" bildirimi gösterilir.
- **Checksum:** İsteğe bağlı SHA-256/MD5 doğrulama. Detay penceresinde hesaplanan SHA-256 gösterilir.
- **Çoklu kaynak (mirror):** v1.1.

---

## 5. Kalıcılık ve veri modeli

### 5.1 Tablolar (GRDB, WAL)

```
downloads(
  id UUID PK, kind [http|media], url, final_url, page_url, referer, user_agent,
  extra_headers JSON, file_name, dest_dir, temp_path, total_bytes NULL, downloaded_bytes,
  status, category, queue_id, priority, max_connections, speed_limit,
  etag, last_modified, accept_ranges BOOL, mime, sha256,
  error_code, error_message, media_options JSON, parent_id NULL (oynatma listesi grubu),
  created_at, started_at, completed_at
)
segments(download_id FK, idx, start, end, received, state)        -- PK(download_id, idx)
queues(id, name, max_concurrent, schedule JSON, sort)
host_profiles(host PK, learned_max_connections, supports_range, last_seen)
categories(id, name, extensions JSON, mime_prefixes JSON, folder NULL, icon, sort, capture BOOL)
```

- **Tercihler:** App Group suite'indeki `UserDefaults` kullanılır. nmh ve appex'in ihtiyaç duyduğu ayarlar da buradan okunur.
- **Çerezler:** Veritabanına **düz metin yazılmaz**. Uygulama yeniden başlayınca sürdürebilmek için indirme başına bir Keychain öğesinde tutulur ve indirme bitince veya silinince temizlenir.
- **Geçmiş:** Saklama süresi ayarlanabilir (sınırsız / 30 gün / tamamlananları temizle).
- **Göçler:** `DatabaseMigrator`.

### 5.2 Durum makinesi

```
queued → probing → downloading ⇄ paused
                     │  ↕
                     │  waitingNetwork
                     ├─→ merging (yalnızca medya) ─→ completed
                     └─→ failed ──(yeniden dene)──→ queued
   (her durumdan) ─→ canceled
```

---

## 6. Arayüz

### 6.1 Yaşam döngüsü (menü çubuğu uygulaması)

- `LSUIElement = YES`: açılışta Dock simgesi ve uygulama menüsü yoktur.
- **Oturum açılışında başlatma:** `SMAppService.mainApp.register()`. İlk kurulum sihirbazı bitince **kendiliğinden etkinleşir** ve Ayarlar'dan kapatılabilir. Durum `.requiresApproval` ise kullanıcı Sistem Ayarları > Genel > Giriş Öğeleri'ne yönlendirilir.
- Oturum açılışında başlayınca hiçbir pencere açılmaz. Uygulama zaten çalışırken Finder'dan tekrar açılırsa ana pencere gösterilir (`applicationShouldHandleReopen`).
- Pencere açılınca `setActivationPolicy(.regular)` ile Dock simgesi, menüler ve ⌘-Tab gelir. Son pencere kapanınca `.accessory`'ye dönülür. Ayar: Dock simgesi her zaman / pencere açıkken / hiçbir zaman.
- `applicationShouldTerminateAfterLastWindowClosed → false`: pencereyi kapatmak uygulamayı kapatmaz.
- Pencere öndeyken ⌘Q'ya basılır ve aktif indirme varsa sorulur: "Kodiz arka planda çalışmaya devam etsin mi?" **[Pencereyi Kapat] [Tamamen Çık]**. Asıl çıkış menü çubuğundaki "Kodiz'den Çık"tır. Çıkarken işçiler düzgünce durdurulur ve durum kaydedilir.
- Dock simgesi görünürken toplam ilerleme Dock döşemesinde (`NSDockTile`) çubuk olarak gösterilir.

### 6.2 Menü çubuğu

```
 ⬇ 48 MB/s  ← simge (isteğe bağlı hız metniyle)
┌──────────────────────────────────────────┐
│ ubuntu-26.04-arm64.iso                   │
│ ███████████░░░░░░  %58 · 48 MB/s · 50 sn ⏸│
│ Xcode_27.xip                             │
│ ███░░░░░░░░░░░░░░  %14 · 12 MB/s · 9 dk  ⏸│
│ 🎬 WWDC26 Keynote (1080p)                │
│ Birleştiriliyor…                         │
│──────────────────────────────────────────│
│ ↓ 60 MB/s · 3 aktif · 2 kuyrukta         │
│ [+ URL Ekle] [Ana Pencere] [⏸ Tümü]  ⚙  │
│ Kodiz'den Çık                            │
└──────────────────────────────────────────┘
```

- Template simge kullanılır. Durumları: boşta, indiriyor (ince ilerleme dolgusu), hata (rozet).
- `MenuBarExtra` (`.window` stili) en fazla 6 aktif indirme ve "Tümünü gör" bağlantısı gösterir.
- Popover'a URL veya bağlantı sürüklenirse indirme eklenir.

### 6.3 Ana pencere

```
┌───────────────────────────────────────────────────────────────────────────────────────┐
│ [+]  [▶] [⏸] [■] [🗑]   [⏸ Tümü] [▶ Kuyruk]                      🔍 Ara…         ⚙  │
├──────────────────┬────────────────────────────────────────────────────────────────────┤
│ İNDİRMELER        │ Dosya adı            Boyut    İlerleme        Hız      Kalan  Bağl. │
│  ◉ Tümü       128 │ 📀 ubuntu-26.04…iso  5,8 GB   ████▌░░ %58     48 MB/s  50 sn  8/8   │
│  ↓ İndiriliyor  3 │ 🗜 Xcode_27.xip      11 GB    █░░░░░░ %14     12 MB/s  9 dk   6/8   │
│  ⏳ Kuyrukta     2 │ 🎬 WWDC26 Keynote    2,1 GB   Birleştiriliyor  —        —      —     │
│  ⏸ Duraklatıldı 1 │ 📄 rapor.pdf         2 MB     ✓ Tamamlandı      —        —      —     │
│  ✓ Tamamlandı 120 │ …                                                                   │
│  ⚠ Başarısız    2 │                                                                     │
│ KATEGORİLER       │                                                                     │
│  🎬 Video   🎵 Müzik   🖼 Resim   📄 Belge   🗜 Arşiv   📦 Uygulama   ⋯ Diğer             │
│ KUYRUKLAR         │                                                                     │
│  Ana Kuyruk  Gece │                                                                     │
├──────────────────┴────────────────────────────────────────────────────────────────────┤
│ ↓ 60 MB/s · 3 aktif · 2 kuyrukta · Boş alan: 412 GB · Hız sınırı: Yok                 │
└───────────────────────────────────────────────────────────────────────────────────────┘
```

- **Kenar çubuğu:** Durum filtreleri, kategoriler (rozet sayılarıyla) ve kuyruklar.
- **Tablo sütunları:** Simge ve dosya adı, Boyut, İlerleme (çubuk ve %), Hız, Kalan süre, Bağlantı (aktif/toplam), Durum, Kategori, Kaynak site, Eklenme, Tamamlanma. Sıralanabilir, gizlenebilir ve yeniden boyutlandırılabilir. Düzen kalıcıdır.
- **Arama (⌘F):** Ad, URL ve site üzerinde. Kenar çubuğu filtresiyle birlikte çalışır.
- **Etkileşim:** Sağ tık menüsü (Aç, Finder'da Göster, Duraklat, Sürdür, Yeniden başlat, Bağlantıyı yenile, URL'yi kopyala, Sil, Dosyayla birlikte sil). Çift tık devam edende detay penceresini, tamamlananda dosyayı açar. Boşluk tuşu Quick Look'u açar. Tamamlanan dosyalar Finder'a sürüklenebilir, pencereye URL sürüklenebilir.
- **Sağ inceleme paneli** (⌘⌥I, isteğe bağlı): seçili öğenin özeti.
- **Performans:** Model güncellemeleri 4 Hz'de toplu yayınlanır, satır kimlikleri sabittir. SwiftUI `Table` 5.000 satırda akıcı kalmazsa ana liste `NSTableView` ile yazılır (Faz 3 kıyaslaması).

> **Not:** "Hangi kanalda hangi indirme var" ifadesini bağlantılar (her bağlantının hangi aralığı hangi hızla indirdiği) ve kuyruklar olarak yorumladım. İkisi de planda var (§17, Soru 8).

### 6.4 Dosya özelinde detay penceresi (IDM tarzı)

```
┌ ubuntu-26.04-desktop-arm64.iso ───────────────────────────────────────────┐
│ URL      https://cdimage.ubuntu.com/…/ubuntu-26.04-desktop-arm64.iso       │
│ Durum    İndiriliyor                 Sürdürme desteği: Evet (Range, ETag)  │
│ Boyut    3,41 GB / 5,82 GB (%58,6)   Kaynak: ubuntu.com                    │
│ Hız      48,2 MB/s (ort. 41,7)       Kalan süre: 50 sn                     │
│ ▕██████▌░░▕████████░▕█████░░░▕███████▕██▌░░░▕█████░▕███░░░░▕████▏         │ ← parça çubuğu
│ ┌ hız grafiği (son 60 sn) ───────────────────────────────────────────────┐ │
│ └────────────────────────────────────────────────────────────────────────┘ │
│  #  Aralık                 İndirilen  Hız        Durum                      │
│  1  0 – 745 MB             745 MB     —          ✓ Tamamlandı → parça 5'i böldü│
│  2  745 MB – 1,49 GB       512 MB     6,1 MB/s   Veri alınıyor              │
│  …                                                                          │
│  8  5,10 – 5,82 GB         88 MB      0          Bekliyor (429, 8 sn)       │
│ Bağlantı: [ 8 ▾ ]   Hız sınırı: [ Yok ▾ ]                                   │
│ ☐ İndirme bitince bu pencereyi otomatik kapat   ☐ Bitince dosyayı aç       │
│ [ Duraklat ]  [ İptal ]  [ Finder'da Göster ]                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

- **Parça çubuğu:** `Canvas` ile çizilir. Genişlik aralıkla orantılıdır. Renkler: indiriliyor (vurgu rengi), bitti (dolu), bekliyor (gri çizgili), hata (kırmızı).
- **Hız grafiği:** Swift Charts ile çizilir.
- **Açılış:** `WindowGroup(id: "detail", for: Download.ID.self)` sayesinde her indirmenin kendi penceresi olur. "Yeni indirmede detay penceresini göster" ayarı vardır (varsayılan: elle eklenenlerde açık, tarayıcıdan gelenlerde kapalı).
- **Medya indirmeleri:** Bağlantı tablosunun yerinde aşamalar gösterilir: *Bilgi alınıyor → Video (1080p, avc1) %xx → Ses (m4a) %xx → Birleştiriliyor → Tamam*. HLS'te parça sayacı (`fragment 412/980`) eklenir.

### 6.5 URL ekleme penceresi
URL alanı (pano otomatik okunur) → anında probe ile dosya adı, boyut, Range desteği ve kategori gösterilir. Ayrıca klasör, bağlantı sayısı, kuyruk ve "Hemen başlat / Kuyruğa ekle" seçenekleri vardır. URL yt-dlp'nin desteklediği bir siteye aitse (YouTube vb.) pencere **video moduna** geçer ve formatları listeler.

### 6.6 Ayarlar

| Sekme | İçerik |
|---|---|
| Genel | Oturum açılışında başlat, Dock simgesi davranışı, menü çubuğunda hız metni, dil, ⌘Q davranışı |
| İndirmeler | Varsayılan klasör, kategori klasörleri, bağlantı sayısı (1–16 / Otomatik), eşzamanlı indirme, genel hız sınırı, yeniden deneme ve zaman aşımı, çakışma politikası, uyku engeli |
| Kategoriler | Uzantı ve MIME eşlemeleri, klasör, yakalama listesine dahil mi |
| Tarayıcılar | Tarayıcı başına bağlantı durumu ("Bağlı · son görülme 2 dk önce"), sihirbazı yeniden çalıştır, yakalanacak türler, en küçük boyut (varsayılan 1 MB), hariç siteler, gizli pencereleri yakala (varsayılan kapalı), video üstü indirme düğmesi |
| Video | Varsayılan ön ayar (≤1080p MP4 / ses MP3 / en iyi), kapsayıcı (MP4/MKV/WebM), çözünürlük üst sınırı, altyazı, meta veri ve kapak gömme, yt-dlp sürümü + "Güncelle" + otomatik günlük kontrol, JS runtime (QuickJS-ng / Deno indir), giriş yapılmış hesaplar |
| Ağ | Sistem proxy'si / özel proxy, User-Agent, host başına bağlantı sınırı, pilde veya pahalı ağda duraklat |
| Bildirimler | Tamamlandı, hata, tarayıcıdan devralındı (varsayılan kapalı), yt-dlp güncellemesi |
| Gelişmiş | Günlükler (gizli bilgiler sansürlü, dışa aktarılabilir), veritabanını dışa/içe aktar, sıfırla |

### 6.7 Bildirimler
`UNUserNotificationCenter` kategorileri ve eylemleri kullanılır. Tamamlandı → **Aç**, **Finder'da Göster**. Hata → **Yeniden Dene**. yt-dlp güncellemesi → **Güncelle**.

### 6.8 macOS'e özgü dokunuşlar
Finder'da dosya üstü ilerleme, Dock İndirilenler yığınının zıplaması, "Nereden" bilgisi, karantina, Quick Look, Hizmetler menüsü ("Kodiz ile indir"), **App Intents / Kestirmeler** ("İndirme ekle", "Tümünü duraklat", "Aktif indirmeler"), `kodiz://add?url=…` URL şeması, sürükle-bırak, SF Symbols, karanlık mod, klavye kısayolları, VoiceOver etiketleri, String Catalog ile TR/EN.

---

## 7. Tarayıcı entegrasyonu

### 7.1 Destek matrisi

| Tarayıcı | Eklenti | Kurulum | Native köprü (manifest yolu, `~/Library/Application Support/` altında) | İndirme yakalama |
|---|---|---|---|---|
| Chrome | MV3 (chromium çıktısı) | Geliştirici modu → "Paketlenmemiş öğe yükle" | `Google/Chrome/NativeMessagingHosts/` (+ Beta/Canary/Chromium) | `downloads` API ✓ |
| Brave | aynı | aynı | `BraveSoftware/Brave-Browser/NativeMessagingHosts/` | ✓ |
| Edge | aynı | aynı | `Microsoft Edge/NativeMessagingHosts/` | ✓ |
| Opera | aynı | `opera://extensions` → Geliştirici modu | ⚠ **Resmî belge yok.** Chrome yolu ve `com.operasoftware.Opera/NativeMessagingHosts/` denenecek, Faz 0'da doğrulanacak | ✓ |
| Vivaldi | aynı | aynı | Chrome yolu + `Vivaldi/NativeMessagingHosts/` (doğrulanacak) | ✓ (en iyi çaba) |
| Firefox | MV3 (firefox çıktısı), **AMO "unlisted" imzalı .xpi** | .xpi Firefox'ta açılır → "Ekle" | `Mozilla/NativeMessagingHosts/` | ✓ |
| Safari | Safari Web Extension (uygulama içindeki .appex) | Safari > Ayarlar > Uzantılar → etkinleştir | appex → Unix soket | ⚠ **`downloads` API yok** (§7.4) |

- **Eklenti dosyaları** `~/Downloads/Kodiz Download Manager/Browser Plugins/{Chromium,Firefox}/` altına kopyalanır.
  - *Not:* Verdiğiniz örnekteki "MC Download Manager" adını Kodiz olarak düzelttim.
- ⚠ Chromium paketlenmemiş eklentiyi **bu klasörden** yükler. Klasör silinirse eklenti çalışmaz. Sihirbaz bunu uyarır, uygulama her açılışta klasörü kontrol edip onarır.
- **Eklenti güncelleme:** Uygulama güncellenince klasördeki dosyalar yenilenir. Eklenti bağlanınca sürümünü bildirir, uygulamadaki sürüm daha yeniyse `chrome.runtime.reload()` ile yeni dosyaları yükler.
- **Firefox:** Kararlı sürüm imzasız eklentiyi yalnızca geçici olarak yükler (yeniden başlatınca kaybolur). Bu yüzden `.xpi` CI'da AMO'nun "unlisted" (listelenmeyen, kendi dağıtımımız) kanalıyla imzalanır.

### 7.2 Eklenti mimarisi (tek kaynak, WXT)

- **Giriş noktaları:**
  - `background`: Chromium'da service worker, Firefox'ta event page.
  - `content`: medya algılama, Safari için tıklama yakalama, video üstü düğme.
  - `popup`: durum, aç/kapa, bu sayfada bulunan medya, "Bu sayfadaki videoyu indir".
  - Ayarların kendisi uygulamada tutulur. Eklenti ayarları `getConfig` ile çeker.
- **Derleme:** `wxt build -b chrome`, `wxt build -b firefox`, `wxt build -b safari` (Xcode appex kaynaklarına kopyalanır).
- **İzinler:** `downloads`, `nativeMessaging`, `cookies`, `contextMenus`, `storage`, `webRequest` (yalnızca gözlem), `scripting`, `<all_urls>`. Her biri README'de gizlilik açısından açıklanır.
- **Sabit kimlikler:** Chromium manifest'inde `"key"` (açık anahtar) bulunur. Böylece eklenti kimliği klasörden bağımsız ve sabittir, NMH `allowed_origins` ile eşleşir. Firefox'ta `browser_specific_settings.gecko.id = "kodiz@kodiz.dev"` kullanılır.
- **Bağlantı:** Uzun ömürlü `runtime.connectNative` portu kullanılır (yapılandırma anlık gönderilir, popup durumu buradan gelir). Yalnızca **indirme devri gerektiğinde** uygulama başlatılır, tarayıcının açılması tek başına uygulamayı başlatmaz.

### 7.3 İndirme devri akışı (Chromium ve Firefox)

```
Tarayıcı                  Eklenti (background)                 kodiz-nmh                 Kodiz
   │ indirme başladı ───► onCreated(item)
   │                       filtre: http(s)? (blob:/data: değil) · tür listede? · boyut ≥ eşik?
   │                       site hariç değil? · POST değil? · ⌥ ile atlanmadı?
   │ ◄── pause(item) ───── duraklat
   │                       topla: finalUrl, referrer, ad, boyut, mime, cookies.getAll({url}),
   │                       navigator.userAgent, sekme URL'si, gizli pencere mi?
   │                       download.add ─────────────────────► soket var mı?
   │                                                            yoksa uygulamayı -g ile başlat,
   │                                                            soket için ≤8 sn bekle ───────► kabul + id
   │                       ◄───────────────────────────────── accepted
   │ ◄── cancel + erase ── (tarayıcı listesinden kaldır)
   │                       HATA / ZAMAN AŞIMI (toplam 10 sn) ► resume(item): tarayıcı devam eder
```

- **POST tespiti:** `webRequest.onBeforeRequest` gözlemiyle `requestId → method` eşlemesi tutulur. POST ile gelen indirme tekrarlanamaz, tarayıcıya bırakılır.
- **Çerezler:** CHIPS bölümlenmiş çerezler için `partitionKey`, Firefox'un first-party isolation özelliği için `firstPartyDomain` dikkate alınır.
- **Atlama:** Bağlantıya **⌥ (Option) basılı tıklanınca** content script bir sonraki indirmeyi işaretler ve tarayıcı indirir. Popup'tan "Bu sitede devre dışı" ya da genel duraklatma seçilebilir.
- **Sağ tık menüsü:** "Kodiz ile indir", "Tüm bağlantıları Kodiz ile indir…" (uygulamada türe göre filtrelenen toplu ekleme penceresi açılır), "Bu videoyu Kodiz ile indir".
- **Dikkat edilecekler:** Tarayıcının "Her dosyanın nereye kaydedileceğini sor" ayarıyla etkileşim test edilecek, gerekirse sihirbaz bu ayarı kapatmayı önerir. Çok küçük dosyalar duraklatma işlemeden önce bitebilir; en küçük boyut eşiği bunu önler.

### 7.4 Safari ayrıntıları

- **Paketleme:** Safari Web Extension, uygulamanın içinde bir `.appex` olarak gelir ve aynı WXT çıktısını kullanır.
- **Safari'de `browser.downloads` API'si yok.** Yakalama şu yollarla yapılır:
  1. Content script, yakalama listesindeki uzantılara giden veya `download` özniteliği taşıyan `<a>` tıklamalarını yakalar (capture fazında `preventDefault`). Uygulama kabul etmezse aynı bağlantı atlama işaretiyle yeniden tıklatılır ve Safari normal şekilde indirir.
  2. Sağ tık menüsünde "Kodiz ile indir".
  3. Medya algılama (§8.2).
  - **Sınırlama:** JS ile başlatılan, form POST ile gelen ya da tıklamadan sonra sunucu yönlendirmesiyle oluşan indirmeler yakalanamaz ve Safari'de normal şekilde iner. Bu sınırlama belgelenecek.
- **Çerezler:** `browser.cookies` kullanılır. HttpOnly çerezlerin kapsamı Faz 5'te doğrulanacak. Yedek yol yt-dlp'nin `--cookies-from-browser safari` seçeneğidir; bu **Tam Disk Erişimi** ister ve isteğe bağlı, rehberli bir adım olarak sunulur.
- **Native köprü:** `browser.runtime.sendNativeMessage` → Safari appex'i başlatır → `SafariWebExtensionHandler.beginRequest` → App Group konteynerindeki Unix sokete bağlanır → uygulama çalışmıyorsa `NSWorkspace` ile onu başlatır (sandbox buna izin verir) → isteği iletir.
- **Dağıtım:** Developer ID ile imzalanmış ve notarize edilmiş uygulamadaki eklenti Safari ayarlarında doğrudan görünür. **İmzasız olursa** kullanıcının her Safari açılışında Geliştir menüsünden "İmzasız uzantılara izin ver"i açması gerekir, bu pratikte kullanılamaz. Bu yüzden Apple Developer üyeliği gerekli (§17, Soru 1).
- **Sihirbaz:** `SFSafariApplication.showPreferencesForExtension` ile Safari'nin uzantı ayarı doğrudan açılır. `SFSafariExtensionManager.getStateOfSafariExtension` ile etkinlik durumu canlı izlenir.

### 7.5 Native Messaging Host (`kodiz-nmh`)

- UI'sı olmayan, imzalı ve hardened küçük bir Swift CLI'dır. `Contents/Helpers/` içinde durur.
- **Protokol:** 4 bayt little-endian uzunluk ve ardından UTF-8 JSON. Host'tan tarayıcıya giden mesaj en fazla 1 MB olabilir.
- **Manifest örneği (Chromium):**
  ```json
  {
    "name": "dev.kodiz.dm",
    "description": "Kodiz Download Manager",
    "path": "/Applications/Kodiz Download Manager.app/Contents/Helpers/kodiz-nmh",
    "type": "stdio",
    "allowed_origins": ["chrome-extension://<SABİT-KİMLİK>/"]
  }
  ```
  Firefox'ta `allowed_origins` yerine `"allowed_extensions": ["kodiz@kodiz.dev"]` kullanılır.
- **Kendini onaran manifestler:** `path` mutlak yol olmak zorunda. Uygulama her açılışta kendi konumunu kontrol eder ve yol değiştiyse tüm manifestleri yeniden yazar.
- **App Translocation:** Uygulama DMG'den veya İndirilenler'den karantinalı hâlde açılırsa macOS onu rastgele bir yola taşır (`SecTranslocateIsTranslocatedURL`). Bu durum algılanınca "Uygulamalar klasörüne taşı" önerilir.
- **Mesaj türleri** (sürümlü): `hello` (sürüm ve tarayıcı adı), `getConfig`, `config.changed` (uygulamadan eklentiye), `download.add`, `download.addBatch`, `media.download`, `status` (popup için özet), `refresh.match` (bağlantı yenileme eşleşmesi).

### 7.6 Köprü sunucusu (uygulama tarafı)

- **Soket:** `<App Group konteyneri>/bridge.sock` (klasör 0700, soket 0600).
- **Karşı taraf doğrulaması:** `LOCAL_PEERTOKEN` ile audit token alınır, `SecCodeCopyGuestWithAttributes` ile kod imzası gereksinimi denetlenir (`anchor apple generic and certificate leaf[subject.OU] = "<TEAMID>" and identifier in {nmh, appex}`). Böylece Mac'teki başka bir süreç Kodiz'e indirme enjekte edemez.
- **Girdi doğrulama:** Yalnızca `http`/`https` şemaları kabul edilir. Başlıklar beyaz listeden geçer, boyut sınırları ve hız sınırlaması uygulanır.

### 7.7 Kurulum sihirbazı

1. **Hoş geldin ve izinler:** Bildirim izni istenir. ~/Downloads erişim izni (TCC) kontrollü biçimde tetiklenir ve nedeni açıklanır.
2. **Oturum açılışında başlat:** Varsayılan açık (`SMAppService`).
3. **Tarayıcı tespiti:** Kurulu tarayıcılar paket kimlikleriyle bulunur (`com.apple.Safari`, `com.google.Chrome`, `com.brave.Browser`, `com.operasoftware.Opera`, `com.microsoft.edgemac`, `org.mozilla.firefox`, `com.vivaldi.Vivaldi`) ve onay kutularıyla listelenir.
4. **Her tarayıcı için ayrı sayfa:**
   - **Chromium türevleri:** (a) dosyalar Browser Plugins klasörüne kopyalanır, (b) NMH manifesti o tarayıcının klasörüne yazılır, (c) "Eklentiler sayfasını aç" düğmesi, (d) kısa animasyonlu anlatım: Geliştirici modu → Paketlenmemiş öğe yükle → klasörü seç, (e) "Klasörü Finder'da göster" ve "Yolu kopyala" (dosya penceresinde ⌘⇧G ile yapıştırmak için), (f) **canlı doğrulama:** o tarayıcıdan `hello` gelince ✓.
   - **Firefox:** `.xpi` Firefox ile açılır → Ekle → canlı ✓.
   - **Safari:** "Safari uzantı ayarlarını aç" → kutuyu işaretle → "Tüm web sitelerinde izin ver" → canlı ✓.
5. **Test indirmesi:** Seçilen tarayıcıda küçük bir test dosyası açılır ve yakalanıp yakalanmadığı doğrulanır.
6. **Bitti:** Uygulama menü çubuğuna çekilir. Sihirbaz Ayarlar > Tarayıcılar'dan yeniden çalıştırılabilir.

---

## 8. Video ve akış indirme

### 8.1 Bileşenler

| Bileşen | Kaynak | Paketteki yeri | Yaklaşık boyut | Güncelleme |
|---|---|---|---|---|
| yt-dlp | Resmî `yt-dlp_macos.zip` (**onedir** PyInstaller; tek dosyalık sürüm her çalıştırmada kendini açtığı için daha yavaş başlar) | `Resources/Tools/yt-dlp/` | ~54 MB (zip) | Uygulama içinden GitHub'dan, `SHA2-256SUMS` doğrulamalı |
| ffmpeg + ffprobe | **Kendi CI derlememiz, LGPL**, universal. Yalnızca gereken muxer/demuxer'lar ve aac/mp3(lame)/opus. x264/x265 gibi GPL bileşenler yok | `Resources/Tools/` | ~30–50 MB | Uygulama sürümüyle |
| QuickJS-ng (`qjs`) | Resmî sürüm (≥ 0.12, optimizasyonlu) | `Resources/Tools/` | ~1,3 MB / mimari | Uygulama sürümüyle |
| Deno (isteğe bağlı) | Resmî `deno-aarch64-apple-darwin.zip` | İndirilebilir | ~38 MB (zip) | Ayarlar > Video |

- **JS runtime neden gerekli?** yt-dlp 2025.11.12'den beri tam YouTube desteği için harici bir JS runtime istiyor.
  - Varsayılan runtime Deno. QuickJS-ng `--js-runtimes quickjs:<yol>` ile kullanılabiliyor. Bun Mayıs 2026'da kullanımdan kaldırıldı.
  - macOS standalone yt-dlp sürümü gerekli EJS betiklerini zaten içeriyor.
  - **Karar:** `.app` küçük kalsın diye QuickJS-ng gömülür. Faz 0'da qjs ile Deno'nun çözümleme süreleri karşılaştırılacak. qjs yavaş çıkarsa Deno ilk YouTube indirmesinde tek seferlik indirilir.
- **İmzalama:** Paketteki tüm çalıştırılabilir dosyalar ve dylib'ler kendi Developer ID'mizle, hardened runtime ve zaman damgasıyla yeniden imzalanır (notarization şartı). yt-dlp onedir'de önce tüm `.dylib`/`.so` dosyaları, sonra ana çalıştırılabilir imzalanır. Bunun notarization'dan sorunsuz geçtiği **Faz 0 spike'ında** doğrulanacak.
- **Çalışma zamanında güncellenen yt-dlp:**
  1. `~/Library/Application Support/Kodiz Download Manager/Tools/yt-dlp-<sürüm>/` klasörüne indirilir. URLSession indirmeleri karantina xattr'ı almaz.
  2. SHA-256 doğrulanır.
  3. `--version` ile duman testi yapılır.
  4. `current` sembolik bağı atomik olarak yeni sürüme çevrilir. Önceki sürüm geri almak için saklanır.
  - Günlük otomatik kontrol yapılır, ayrıca **tek tıkla güncelleme** düğmesi vardır. "HTTP 403" gibi hatalarda doğrudan "yt-dlp'yi güncelle" önerilir.

### 8.2 Medya algılama (eklenti)

- `<video>`, `<audio>` ve `<source>` öğeleri taranır. `blob:` kaynaklı bir video MSE kullanıldığını gösterir; bu durumda manifest ağ trafiğinden bulunur.
- Sayfa bağlamında `PerformanceObserver('resource')` ile `.m3u8`, `.mpd`, `.ism` ve medya dosyası URL'leri yakalanır. Bu yöntem tüm tarayıcılarda, Safari dahil, çalışır.
- Chromium ve Firefox'ta ek olarak `webRequest` gözlemiyle iframe'ler dahil Content-Type'a göre (`application/vnd.apple.mpegurl`, `application/dash+xml`, `video/*`) yakalama yapılır.
- Araç çubuğu rozeti bulunan medya sayısını gösterir. Popup'ta "Sayfa videosu (yt-dlp)", çözülmüş HLS kaliteleri ve doğrudan dosyalar (boyutlarıyla) listelenir.
- **Video üstü düğme:** Fareyle üzerine gelinen `<video>` öğesinde "⬇ Kodiz ile indir" düğmesi çıkar. Ayarlanabilir, sorun çıkaran sitelerde kapatılabilir.
- **YouTube ve yt-dlp'nin desteklediği siteler:** Sayfa URL'si yt-dlp'ye gönderilir. Tek tık varsayılan ön ayarı kullanır, ⌥ veya sağ tık format seçiciyi açar.

### 8.3 yt-dlp çalıştırma

Argümanlar dizi olarak verilir, **kabuk kullanılmaz**. URL'den önce `--` konur (`-` ile başlayan URL'lerle seçenek enjeksiyonunu önlemek için):

```
yt-dlp --no-config
  --ffmpeg-location <Tools>/ffmpeg
  --js-runtimes quickjs:<Tools>/qjs              # veya deno:<yol>
  -S "res:1080,vcodec:h264,ext:mp4:m4a"          # ≤1080p, QuickTime uyumlu; kesin sözdizimi Faz 6'da sabitlenecek
  --merge-output-format mp4
  --cookies <tmp>/kdm-cookies-<id>.txt           # 0600 izinli, iş bitince silinir
  --user-agent "<tarayıcı UA>" --referer "<sayfa URL>"
  -N 4                                           # HLS/DASH parça paralelliği
  --newline --progress-template "download:KDM %(progress)j"
  --print "after_move:KDMFILE %(filepath)s"
  --no-playlist                                  # liste ise kullanıcıya sorulur
  -P "<hedef>" -P "temp:<geçici>" -o "%(title).200B [%(id)s].%(ext)s"
  [--embed-metadata --embed-thumbnail --embed-subs --sub-langs tr,en]   # isteğe bağlı
  [--limit-rate <genel sınır>]
  -- <URL>
```

- **İlerleme:** `KDM` önekli JSON satırları ayrıştırılır (indirilen, toplam veya tahmini toplam, hız, ETA, parça sırası). `[Merger]`, `[ExtractAudio]` ve `[EmbedThumbnail]` satırları aşamaları belirler.
- **Duraklat / sürdür:** Süreç grubuna SIGINT gönderilir. Aynı komutla yeniden başlatılınca yt-dlp `.part` dosyalarından devam eder (HLS'te parça düzeyinde).
- **Hata eşleme:**

  | yt-dlp mesajı | Kodiz'in önerisi |
  |---|---|
  | "Sign in to confirm your age" | Giriş penceresi veya tarayıcı çerezleri |
  | "confirm you're not a bot" | Tarayıcı çerezleri |
  | "HTTP Error 403" | yt-dlp'yi güncelle |
  | "Requested format is not available" | Format seçiciyi aç |
  | DRM | "DRM korumalı içerik desteklenmiyor" |

- **Format seçici:** `yt-dlp -J` çıktısı ayrıştırılır ve gruplanır: Video + Ses (çözünürlük, codec, fps, tahmini boyut), Yalnızca ses (M4A/Opus veya MP3'e dönüştür, `-x --audio-format mp3`), Altyazılar. JSON birkaç dakika önbellekte tutulur.
- **Oynatma listeleri:** `_type: playlist` gelirse "Yalnızca bu video / Tüm liste (N video)" sorulur. Liste, tabloda alt işleri olan bir grup satırı olarak görünür.

### 8.4 Çerezler ve giriş penceresi

- **Birincil yol:** Eklenti, sayfanın alan adına ait çerezleri gönderir. Kodiz bunları Netscape biçiminde bir dosyaya yazar (HttpOnly çerezler `#HttpOnly_` önekiyle). Dosyanın izni 0600'dür ve iş bitince silinir.
- **Uygulama içi giriş penceresi:** Kalıcı ve ayrı bir `WKWebsiteDataStore(forIdentifier:)` kullanan bir WKWebView'dir. Kullanıcı siteye giriş yapar, çerezler `httpCookieStore.getAllCookies` ile alınır. Hesaplar Ayarlar > Video'da listelenir ve "Çıkış yap / Temizle" ile silinebilir.
- ⚠ **Risk:** Google girişi gömülü WebView'leri sıkça engeller ("Bu tarayıcı veya uygulama güvenli olmayabilir"). Bu yüzden **YouTube'un yaş doğrulaması için öncelikli yol tarayıcı çerezleridir.** Giriş penceresi diğer siteler için ve yedek olarak sunulur.
- yt-dlp belgelerine göre YouTube, açık tarayıcı sekmelerinde hesap çerezlerini döndürür. Bu nedenle sorun çıkarsa kullanıcıya rehber gösterilir.

### 8.5 Doğrudan HLS/DASH
Yakalanan `.m3u8` veya `.mpd` manifesti, başlıklarıyla birlikte (Referer, çerez, UA) yt-dlp'nin generic extractor'una verilir. Parçalar `-N` ile paralel iner, ffmpeg ile MP4'e remux edilir. AES-128 şifreli HLS desteklenir; bu DRM değildir. SAMPLE-AES/FairPlay/Widevine desteklenmez.

### 8.6 Hibrit hızlandırma (v1.1, deneysel)
Seçilen formatın protokolü doğrudan `https` ise video ve ses akışları `-J` çıktısındaki `http_headers` ile **Kodiz'in kendi çok bağlantılı motoruyla** indirilir, ardından ffmpeg `-c copy` ile birleştirilir. Böylece YouTube'da da bağlantı tablosu ve IDM tarzı hız elde edilir. Özellik bayrağı arkasında çalışır, 403 alınırsa yt-dlp'ye geri dönülür.

---

## 9. Kategoriler (varsayılan eşlemeler)

| Kategori | Uzantılar (MIME türü de dikkate alınır) | Varsayılan olarak yakalanır mı? |
|---|---|---|
| Video | mp4 mkv mov avi webm m4v flv wmv mpg mpeg 3gp ts | ✓ |
| Müzik | mp3 m4a aac flac wav ogg opus wma aiff alac | ✓ |
| Resim | jpg jpeg png gif webp heic heif svg bmp tiff avif raw | ✗ |
| Belge | pdf doc(x) xls(x) ppt(x) pages numbers key txt rtf epub odt csv | ✗ (PDF tarayıcıda açılsın) |
| Arşiv | zip rar 7z tar gz bz2 xz tgz zst iso | ✓ |
| Uygulama | dmg pkg mpkg ipa exe msi apk deb rpm appimage | ✓ |
| Diğer | — | ✗ |

Uzantı yoksa `Content-Type` üzerinden `UTType` ile kategori belirlenir. Kategori listesi hem kenar çubuğunu hem de eklentinin yakalama listesini besler ve tek doğruluk kaynağı uygulamadır. Varsayılan en küçük yakalama boyutu 1 MB'dir.

---

## 10. Güvenlik ve gizlilik

- **Telemetri yok.** İndirmeler dışındaki tek ağ çağrıları güncelleme kontrolleridir (Sparkle appcast ve yt-dlp için GitHub API). Belgelenir ve kapatılabilir.
- Köprüde kod imzasına dayalı karşı taraf doğrulaması ve girdi doğrulaması yapılır. Kabuk yoktur, argümanlar dizi olarak verilir, URL'den önce `--` konur.
- Çerezler bellekte ve Keychain'de tutulur. Geçici çerez dosyaları 0600 izinlidir ve silinir. Günlüklerde `Cookie`/`Authorization` başlıkları ve URL'deki token parametreleri sansürlenir.
- Tüm indirilen dosyalara **karantina xattr'ı** yazılır, Gatekeeper atlanmaz.
- Araç güncellemeleri yalnızca HTTPS ile alınır, SHA-256 ile doğrulanır ve geri alınabilir. Uygulama güncellemeleri Sparkle EdDSA ile imzalıdır.
- Gizli pencereler varsayılan olarak yakalanmaz.
- Safari appex sandbox'lıdır ve en az yetkiyle çalışır.

---

## 11. İmzalama, paketleme, dağıtım

- **Apple Developer Program (yıllık 99 USD):** Developer ID Application sertifikası, notarytool, Team ID (App Group öneki için) ve Safari eklentisinin sorunsuz çalışması için gerekli.
- **Kimlikler** (alan adına göre kesinleşecek): `dev.kodiz.DownloadManager`, `…SafariExtension`, `…NativeHost`. App Group: `<TEAMID>.dev.kodiz.DownloadManager`. Team ID önekli biçim, macOS 15+ üzerinde App Store dışı uygulamalarda konteyner erişim izni sorusunu önler.
- **Entitlement'lar:**
  - Uygulama: hardened runtime, `application-groups`.
  - appex: `app-sandbox`, `application-groups`.
  - Deno yeniden imzalanırsa: `allow-jit`.
- **İmza sırası** (`--deep` kullanılmaz, içten dışa): Tools dylib'leri → Tools çalıştırılabilirleri → nmh → appex → uygulama.
- **Paketleme:** DMG (Uygulamalar'a sürükle arka planlı) Sparkle için ayrıca `.zip`. DMG notarize edilir ve staple yapılır. Tahmini boyut: `.app` ~150–200 MB, DMG ~80–100 MB.
- **Sparkle 2:** `appcast.xml` GitHub Pages'ta durur. EdDSA anahtarıyla imzalanır. Kararlı ve beta kanalları vardır.
- **Güncelleme sonrası:** Manifestler ve Browser Plugins klasörü yenilenir, eklentiler sürüm el sıkışmasıyla kendini yeniden yükler.
- **Homebrew:** Önce kendi tap'imiz (`brew install --cask <kullanıcı>/tap/kodiz-download-manager`). Resmî homebrew-cask, popülerlik ölçütleri karşılanınca.

---

## 12. CI/CD (GitHub Actions)

| İş akışı | Tetikleyici | Adımlar |
|---|---|---|
| `ci.yml` | PR / push | macOS arm64 runner → XcodeGen → derleme → KodizKit birim testleri + TestServer entegrasyon testleri → SwiftLint/SwiftFormat → eklenti: lint, typecheck, Vitest, `wxt build` (tüm hedefler) |
| `tools.yml` | Elle / haftalık | ffmpeg LGPL universal derleme (sürüme göre önbellekli) → yt-dlp_macos.zip ve qjs indir → SHA-256 doğrula → `versions.json` güncelleme PR'ı |
| `release.yml` | `v*` etiketi | Release universal derleme → imza (secrets: `DEVELOPER_ID_P12`, `P12_PASSWORD`) → notarytool (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`) → staple → DMG + ZIP → Sparkle `sign_update` (`SPARKLE_ED_PRIVATE_KEY`) → appcast → Firefox `web-ext sign --channel=unlisted` (`AMO_JWT_ISSUER/SECRET`) → GitHub Release |

---

## 13. Test stratejisi

- **Birim testleri:**
  - Parça planlayıcı (bölme, iş çalma, sınır hesapları), AIMD denetleyicisi, hız sınırlayıcı, yeniden deneme politikası
  - `Content-Disposition` ayrıştırıcısı, dosya adı temizleyici, kategori eşleme
  - yt-dlp ilerleme ayrıştırıcısı, Netscape çerez yazıcısı, NMH çerçeveleme
- **Entegrasyon:** `Tools/TestServer` hata profilleri:
  - Range var/yok, Range isteğine 200 dönen sunucu, hatalı `Content-Range`
  - `Retry-After`'lı 429, 503 fırtınası, yavaş bağlantılar, rastgele ofsette kopma
  - İndirme ortasında değişen ETag, yönlendirme zinciri, süresi dolan imzalı URL
  - gzip zorlayan sunucu, bilinmeyen uzunluk / chunked yanıt
  - 10 GB seyrek dosya, Unicode `Content-Disposition`, HTTP/1.1 ve HTTP/2
- **Çökme ve sürdürme:** Rastgele anlarda `kill -9`, 100 tekrar. Her seferinde son SHA-256 eşleşmeli.
- **Performans:** Loopback üzerinde verim ölçümü, Instruments ile CPU, bellek ve sızıntı profili, 5.000 satırda arayüz akıcılığı.
- **Eklenti:** Vitest. Playwright ile Chromium'a paketlenmemiş eklenti ve sahte NMH yüklenerek e2e testi. Firefox için `web-ext run`. Safari için elle kontrol listesi.
- **Elle test matrisi:**
  - macOS 14 / 15 / 26 / 27 × Apple Silicon ve Intel
  - Tarayıcılar: Chrome, Brave, Opera, Edge, Firefox, Safari
  - Uygulama açık/kapalı, temiz kurulum ve güncelleme, uygulamanın yerinin değişmesi
- **Video duman testleri** (CI dışında, gecelik): YouTube (normal, yaş kısıtlı, Shorts, oynatma listesi), Vimeo, Apple'ın HLS test akışları.

---

## 14. Yol haritası

> Süreler tek geliştirici ve tam zamanlı çalışma için kaba tahmindir. Claude Code ile birlikte çalışınca kısalabilir.

| Faz | Kapsam | Çıktı / "Bitti" ölçütü | Süre |
|---|---|---|---|
| **0 — Temel ve spike'lar** | Repo, XcodeGen, KodizKit iskeleti, CI iskeleti. **Spike'lar:** (1) URLSession'da oturum başına ayrı TCP ve HTTP/2'de hız farkı, (2) yt-dlp onedir'in kendi imzamızla notarization'dan geçmesi, (3) appex ↔ uygulama Unix soket iletişimi (App Group), (4) Opera ve Vivaldi NMH yolları, (5) qjs ile Deno'nun YouTube çözümleme süreleri | Spike raporları `docs/spikes/` altında, plan güncellenmiş | 1 hafta |
| **1 — Motor çekirdeği** | Probe, parça planlayıcı, işçiler, FileWriter, yeniden deneme, AIMD, hız sınırlayıcı, dosya adı mantığı, `kdm-cli`, TestServer | `kdm-cli` 8 bağlantıyla 1 Gbps'e ulaşıyor. Tüm hata profilleri geçiyor. 10 GB dosya doğrulanıyor | 2–3 hafta |
| **2 — Kalıcılık ve sürdürme** | GRDB şeması, checkpoint, durum makinesi, kuyruk ve zamanlayıcı, ağ ve uyku yönetimi, karantina/WhereFroms, Finder ilerlemesi | `kill -9` testi 100/100. Uyku ve ağ kopmasından sonra otomatik devam | 1–2 hafta |
| **3 — Arayüz** | Menü çubuğu yaşam döngüsü, MenuBarExtra, ana pencere, detay penceresi (parça çubuğu, bağlantı tablosu, grafik, otomatik kapat), URL ekleme, ayarlar, bildirimler, sihirbaz iskeleti, TR/EN | **M1: Kendi kullanımımız.** URL yapıştırarak tam kullanılabilir, 5.000 satırda akıcı | 3 hafta |
| **4 — Tarayıcı: Chromium + Firefox** | kodiz-nmh, köprü sunucusu ve imza doğrulaması, WXT eklentisi (yakalama, popup, sağ tık), manifest kurucu ve onarım, sihirbaz sayfaları ve canlı doğrulama, AMO imzalama | Chrome, Brave, Edge, Opera ve Firefox'ta yakalama ve yedek yol çalışıyor. Uygulama kapalıyken < 3 sn'de devir | 2–3 hafta |
| **5 — Safari** | appex hedefi, handler, tıklama yakalama, sağ tık, çerez yolu, `SFSafariExtensionManager` ile sihirbaz kontrolü | Safari'de tıklama ve sağ tıkla devir çalışıyor. Başarısız olunca Safari indirmeye devam ediyor | 1–2 hafta |
| **6 — Video** | Araç hattı (ffmpeg LGPL, yt-dlp, qjs) ve imzalama, medya çalıştırıcı, ilerleme, format seçici, oynatma listesi, eklentide medya algılama ve video üstü düğme, çerez dosyası, giriş penceresi, yt-dlp güncelleyici, hata eşleme | **M2: Beta.** YouTube'da tek tıkla 1080p MP4, tarayıcı çerezleriyle yaş kısıtlı video, HLS test akışı, yt-dlp güncelleme ve geri alma | 3 hafta |
| **7 — Cila** | App Intents/Kestirmeler, Hizmetler, URL şeması, pano izleme, Quick Look, erişilebilirlik, Liquid Glass gözden geçirmesi, performans ayarı, sızıntı kontrolleri, yardım belgeleri | Bilinen kritik hata yok | 1–2 hafta |
| **8 — Yayın (GitHub)** | İmza ve notarization hattı, DMG, Sparkle, README (TR + EN), ekran görüntüleri, LICENSE/NOTICE, CONTRIBUTING, SECURITY, issue şablonları, Homebrew tap | **v1.0.0 GitHub Release** | 1 hafta |

**Toplam:** ~15–20 hafta.

**v1.1 ve sonrası:** Hibrit video hızlandırma (§8.6), çoklu kaynak (mirror), Metalink, "kuyruk bitince bilgisayarı kapat", Chrome Web Store / Edge / AMO'da listelenen mağaza sürümleri (YouTube özelliği olmadan, §16), site bazlı kurallar, iPhone'dan Mac'e "bunu indir" (Paylaş menüsü).

---

## 15. Risk kaydı

| Risk | Olasılık | Etki | Önlem |
|---|---|---|---|
| YouTube değişiklikleri yt-dlp'yi bozar | Yüksek | Yüksek | Tek tıkla ve günlük otomatik güncelleme, hata mesajında "Güncelle" önerisi, geri alma |
| Safari'de `downloads` API'sinin olmaması | Kesin | Orta | Tıklama yakalama, sağ tık, medya algılama. Sınırlamalar belgelenir |
| Opera/Vivaldi NMH yolları belgelenmemiş | Orta | Orta | Faz 0 spike'ı, birden çok yola yazma, sihirbazda canlı doğrulama |
| Chrome Web Store YouTube indiricilerine izin vermiyor | Kesin | Düşük (v1 mağaza kullanmıyor) | Paketlenmemiş dağıtım. İleride YouTube'suz mağaza sürümü |
| Firefox imzasız eklentiyi kalıcı yüklemiyor | Kesin | Orta | AMO "unlisted" imzalama CI'da |
| Google girişinin WKWebView'de engellenmesi | Yüksek | Orta | Öncelikli yol tarayıcı çerezleri |
| PyInstaller ikilisi ile hardened runtime/notarization uyumsuzluğu | Orta | Yüksek | Faz 0 spike'ı. Yedek: yt-dlp'yi ilk kullanımda indirmek |
| HTTP/2 çoklaması paralelliği yok eder | Orta | Yüksek | Bağlantı başına ayrı URLSession. Yedek: NIO + HTTP/1.1 |
| Sunucunun çok bağlantı nedeniyle engellemesi | Orta | Orta | AIMD, host hafızası, host başına toplam sınır |
| Apple Developer üyeliği olmaması | ? | Yüksek | §17, Soru 1 |
| TCC izinleri (İndirilenler, Tam Disk Erişimi) | Kesin | Düşük | Sihirbazda açıklamalı ve kontrollü izin akışı |
| Hukuki (YouTube kullanım şartları, telif) | Orta | Orta | Sorumluluk reddi, DRM'ye dokunulmaması, kullanıcı sorumluluğu |

---

## 16. Lisans ve hukuki notlar

- **Uygulama:** MIT (önerilen; Apache-2.0 de olabilir).
- **Üçüncü taraflar:** yt-dlp (Unlicense), ffmpeg (**LGPL-2.1+**: derleme yapılandırması ve kaynak bağlantısı NOTICE dosyasında yer alır, GPL bileşen kullanılmaz), QuickJS-ng (MIT), Deno (MIT, isteğe bağlı), Sparkle (MIT), GRDB (MIT), WXT (MIT).
- **Sorumluluk reddi:** İçerik ve kullanım şartları kullanıcının sorumluluğundadır. DRM aşılmaz. Proje YouTube, Google veya Apple ile bağlantılı değildir.
- **Mağaza politikaları:** Chrome Web Store, YouTube indirmeyi kolaylaştıran eklentilere izin vermiyor. Bu yüzden v1 eklentisi uygulamayla birlikte paketlenmemiş olarak dağıtılır.
- **Ad:** Yayından önce "Kodiz" için marka araştırması yapılmalı. Sihirbazda tarayıcı logoları yerine adlar ve genel simgeler kullanılır.

---

## 17. Açık sorular

Yanıt gelene kadar her sorunun "Varsayılan" sütunundaki seçenekle ilerleniyor.

| # | Soru | Varsayılan |
|---|---|---|
| 1 | **Apple Developer Program üyeliğiniz var mı ya da alacak mısınız?** Notarization, Safari eklentisi ve App Group için pratikte şart. Yoksa uygulama Gatekeeper uyarısıyla açılır ve Safari eklentisi her Safari açılışında elle izin ister | Alınacak |
| 2 | Minimum macOS 14 Sonoma ve Intel desteği (Universal) uygun mu? | Evet / Evet |
| 3 | Lisans: MIT mi, GPL-3.0 mı? | MIT |
| 4 | Bundle ID için bir alan adınız var mı (ör. `kodiz.dev`)? GitHub kullanıcı veya organizasyon adı ne olacak? | `dev.kodiz.*` (geçici) |
| 5 | Eklenti klasörü `~/Downloads/Kodiz Download Manager/Browser Plugins/` olsun mu? Örnekte "MC Download Manager" yazıyordu | Kodiz adıyla |
| 6 | Varsayılan indirme klasörü `~/Downloads` (kategori alt klasörleri kapalı) olsun mu? | Evet |
| 7 | Edge ve Vivaldi de resmî olarak desteklensin mi? (Aynı eklenti, ek maliyet çok düşük) | Evet |
| 8 | "Hangi kanalda hangi indirme var" derken bağlantıları mı (her bağlantının aralığı ve hızı), kuyrukları mı kastettiniz? | İkisi de planda |
| 9 | Hibrit video hızlandırma (YouTube'u kendi motorumuzla çok bağlantılı indirmek) v1.0'da mı olsun, v1.1'de mi? | v1.1 |
| 10 | Arayüz dili TR + EN yeterli mi? | Evet |

---

## Ek A — Native messaging manifest yolları

Hepsi `~/Library/Application Support/` altındadır:

| Tarayıcı | Klasör | Durum |
|---|---|---|
| Chrome | `Google/Chrome/NativeMessagingHosts/` | Belgeli |
| Chrome Beta / Canary / Chromium | `Google/Chrome Beta/…`, `Google/Chrome Canary/…`, `Chromium/…` | Belgeli |
| Brave | `BraveSoftware/Brave-Browser/NativeMessagingHosts/` | Yaygın kullanım |
| Edge | `Microsoft Edge/NativeMessagingHosts/` | Belgeli |
| Opera | `com.operasoftware.Opera/NativeMessagingHosts/` + Chrome yolu | **Doğrulanacak** |
| Vivaldi | `Vivaldi/NativeMessagingHosts/` + Chrome yolu | **Doğrulanacak** |
| Firefox | `Mozilla/NativeMessagingHosts/` | Belgeli |

## Ek B — Köprü mesajı örneği

```json
{
  "v": 1,
  "id": "6f1c…",
  "type": "download.add",
  "browser": "chrome",
  "payload": {
    "url": "https://example.com/files/app.dmg",
    "referrer": "https://example.com/download",
    "pageUrl": "https://example.com/download",
    "fileNameHint": "app.dmg",
    "totalBytes": 184320000,
    "mime": "application/x-apple-diskimage",
    "userAgent": "Mozilla/5.0 (Macintosh; …)",
    "cookies": [{ "name": "sid", "value": "…", "domain": ".example.com", "path": "/",
                  "secure": true, "httpOnly": true, "expirationDate": 1792000000 }],
    "incognito": false
  }
}
```

Yanıt: `{ "v": 1, "id": "6f1c…", "ok": true, "downloadId": "…" }` ya da `{ "ok": false, "reason": "rejected|timeout|unsupported" }` (bu durumda tarayıcı indirmeye devam eder).
