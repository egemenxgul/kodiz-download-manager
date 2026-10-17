# Kodiz Download Manager (KDM) 🚀

[![CI](https://github.com/egemenxgul/kodiz-download-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/egemenxgul/kodiz-download-manager/actions)
[![License: PolyForm Noncommercial 1.0.0](https://img.shields.io/badge/License-PolyForm%20Noncommercial-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014%2B%20(Sonoma%2B)-black.svg)]()
[![Architecture](https://img.shields.io/badge/Arch-Universal%20(Apple%20Silicon%20%2B%20Intel)-orange.svg)]()

> **Kodiz Download Manager**, macOS için yerel (Swift 6 + SwiftUI) ve açık kaynaklı, çok bağlantılı bir indirme yöneticisidir. IDM tarzı dinamik parçalama ve verim, tek kaynaklı modern tarayıcı eklentisi, yt-dlp tabanlı video yakalama ve menü çubuğuna entegre arayüz sunar.

---

## 🌟 Öne Çıkan Özellikler

- ⚡ **Yüksek Hızlı Çok Bağlantılı Motor:** Dosyaları dinamik parçalara böler. Her bağlantı için ayrı bir `URLSession` açarak HTTP/2 çoklama sınırını aşar ve gerçek TCP paralelliği sağlar.
- 🧩 **Dinamik Parçalama (Work Stealing):** Boşa çıkan bağlantılar, devam eden en büyük parçayı 64 KiB'ye hizalı bölerek indirir; "son parçayı bekleme" sorununu ortadan kaldırır.
- 🌐 **Tek Kaynaklı Tarayıcı Eklentisi:** WXT ve TypeScript ile yazılmış Manifest V3 eklentisi. Chrome, Brave, Edge, Opera, Vivaldi, Firefox ve Safari'de indirmeleri anında yakalar.
- 🎬 **Video ve Akış İndirme:** `yt-dlp`, `ffmpeg` (LGPL universal) ve `QuickJS-ng` çalışma zamanı ile YouTube ve binlerce siteden tek tıkla medya indirme.
- 🎨 **Yerel macOS Arayüzü:** Menü çubuğu (`MenuBarExtra`), kenar çubuğu kategorileri, `Canvas` ile IDM tarzı bağlantı parça çubuğu ve detay pencereleri.
- 💾 **Çökmeye Dayanıklı Kalıcılık:** SQLite + GRDB (WAL kipi) ve `fsync` kontrol noktaları sayesinde beklenmedik kapanmalarda bayt kaybı yaşanmaz.
- 🛡️ **macOS Uyumu:** `com.apple.quarantine` (Gatekeeper denetimi), `kMDItemWhereFroms`, Dock zıplatma bildirimi ve uyku engelleme (`IOPMAssertion`).

---

## 📁 Proje Mimarisi

```
Kodiz Download Manager.app
└── Contents
    ├── MacOS/Kodiz Download Manager      ← Ana süreç (LSUIElement, non-sandboxed, hardened)
    ├── Helpers/kodiz-nmh                 ← Native messaging host (CLI, stdio JSON)
    ├── PlugIns/KodizSafari.appex         ← Safari Web Extension (sandboxed)
    ├── Resources/Tools/
    │   ├── yt-dlp/                       ← yt-dlp onedir çalıştırılabilir
    │   ├── ffmpeg, ffprobe               ← LGPL universal derleme
    │   └── qjs                           ← QuickJS-ng JS runtime
    └── Resources/BrowserExtensions/      ← Chromium & Firefox eklenti paketleri
```

### Modüller (`Packages/KodizKit`)
- **`KodizEngine`**: Range probe, parça planlayıcı, bağlantı işçileri, FileWriter (`pwrite`), AIMD hız denetleyicisi, hız sınırlayıcı.
- **`KodizStore`**: GRDB modelleri, SQLite WAL veritabanı ve göçler.
- **`KodizBridgeProtocol`**: Tarayıcı eklentisi, Native Host ve App arasındaki IPC protokolü ve Unix domain socket sunucusu.
- **`KodizMedia`**: yt-dlp çalıştırıcı, ilerleme ayrıştırıcı ve Netscape çerez dışa aktarıcısı.
- **`KodizSystem`**: Oturum açılış öğesi (`SMAppService`), uyku engeli, `NWPathMonitor`, karantina xattr'ları.

---

## 🛠️ Geliştirme ve Derleme

### Gereksinimler
- macOS 14.0 (Sonoma) veya üzeri
- Xcode 16+ (Swift 6.0+)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Node.js 20+ (Tarayıcı eklentisi için)

### Testleri Çalıştırma
```bash
swift test --package-path Packages/KodizKit
```

### Xcode Projesini Oluşturma ve Derleme
```bash
# Xcode projesini oluştur
xcodegen generate

# Terminalden derle
xcodebuild -project KodizDownloadManager.xcodeproj \
           -scheme "Kodiz Download Manager" \
           build CODE_SIGNING_ALLOWED=NO
```

### Tarayıcı Eklentisini Derleme
```bash
cd Extension
npm install
npm run build         # Chrome / Chromium MV3
npm run build:firefox # Firefox
npm run build:safari  # Safari
```

---

## 📄 Lisans

Kodiz Download Manager **[PolyForm Noncommercial License 1.0.0](LICENSE)** ile lisanslanmıştır. Kaynak kodu açıktır, ancak bu bir ticari açık kaynak lisansı değildir:

- **Serbest:** Kişisel kullanım, öğrenme, araştırma, hobi projeleri ve deneme; okullar, üniversiteler, dernekler, vakıflar ve kamu kurumları gibi ticari olmayan kuruluşlar. Bu amaçlarla yazılımı değiştirebilir ve dağıtabilirsiniz.
- **İzne Tabi (Yasak):** Her türlü ticari kullanım, satış, ücretli dağıtım, ticari bir ürüne/hizmete dahil etme veya ticari amaçla yayınlama. Ticari lisans ve izinler için proje sahibiyle iletişime geçin.
- **Atıf Zorunlu:** Yazılımın tamamını veya bir kısmını alan herkes [LICENSE](LICENSE) dosyasındaki `Required Notice:` satırını ve lisans koşullarını korumak zorundadır.

Kullanılan üçüncü taraf bileşenler (`ffmpeg` LGPL-2.1, `yt-dlp` Unlicense, `QuickJS-ng` MIT, `GRDB` MIT) kendi açık kaynak lisanslarına tabidir.
