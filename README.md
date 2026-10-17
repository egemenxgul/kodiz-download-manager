# Kodiz Download Manager (KDM) 🚀

> **Durum:** Erken geliştirme (alfa öncesi)

[![CI](https://github.com/egemenxgul/kodiz-download-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/egemenxgul/kodiz-download-manager/actions)
[![License: PolyForm Noncommercial 1.0.0](https://img.shields.io/badge/License-PolyForm%20Noncommercial-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014%2B%20(Sonoma%2B)-black.svg)]()
[![Architecture](https://img.shields.io/badge/Arch-Universal%20(Apple%20Silicon%20%2B%20Intel)-orange.svg)]()

> **Kodiz Download Manager**, macOS için yerel (Swift 6 + SwiftUI) ve kaynak kodu açık (PolyForm Noncommercial 1.0.0), çok bağlantılı bir indirme yöneticisidir. IDM tarzı dinamik parçalama ve verim, tek kaynaklı modern tarayıcı eklentisi, menü çubuğuna entegre arayüz ve çökmeye dayanıklı indirme motoru sunar.

---

## 🌟 Özellik Durumu

### ✅ Çalışıyor (Testlerle Doğrulandı)
- ⚡ **Yüksek Hızlı Çok Bağlantılı Motor:** 8 bağımsız `URLSession` ile gerçek TCP paralelliği (T1-T13 testleri geçti; loopback testinde Apple Silicon'da > 2 GB/s aktarım).
- 🧩 **Dinamik Parçalama & İş Çalma (Work Stealing):** Boşa çıkan işçilerin yavaş parçaları bölerek indirmesi (T6 testi ile doğrulandı).
- ⏯️ **Duraklatma / Sürdürme:** `If-Range` desteği ve atomik `fsync` kontrol noktalarıyla mükemmel bayt devamlılığı (T11 & T12 çökme testleri geçti).
- 🌐 **Tek Kaynaklı Tarayıcı Eklentisi:** WXT + TypeScript Manifest V3 eklentisi (Chrome, Firefox, Safari derlemeleri hazır; dosya uzantısı/boyut filtreleme, ⌥ Option ile atlama, debounced medya algılama Vitest ile test edildi).
- 🔌 **Native Messaging Köprüsü:** `BridgeServer`, `NativeMessagingHost` ve `SafariWebExtensionHandler` üzerinden güvenli Unix domain socket IPC iletişimi.
- 💾 **Kalıcılık & Çerez Yönetimi:** SQLite + GRDB kontrol noktası deposu, çerezler için güvenli macOS Keychain saklama.
- 🎨 **macOS Arayüzü:** SwiftUI ana penceresi, IDM tarzı bağlantı parça tuvali (`SegmentCanvasView`), menü çubuğu (`MenuBarExtra`) ve `LSUIElement` arka plan desteği.

### 🔄 Geliştiriliyor
- 🎬 **Video ve Akış İndirme:** `yt-dlp` ve `QuickJS-ng` universalleri hazırlandı (`Scripts/fetch-tools.sh`); UI format seçici ve giriş penceresi entegrasyonu devam ediyor.
- 🌐 **Canlı Safari Appex Entegrasyonu:** Kod imzalı App Group ve Safari Developer sertifikası ile canlı tarayıcı testi.

### 📋 Planlanan
- 🎞️ **ffmpeg Entegrasyonu:** Çok parçalı HLS/DASH birleştirme ve dönüştürme için LGPL universal derleme.
- ⚡ **Gelişmiş Zamanlayıcı:** Belirli saatlerde indirmeyi başlatma/durdurma ve kuyruk sıralama.

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
    │   └── qjs                           ← QuickJS-ng universal JS runtime
    └── Resources/BrowserExtensions/      ← Chromium & Firefox eklenti paketleri
```

### Modüller (`Packages/KodizKit`)
- **`KodizEngine`**: Range probe, parça planlayıcı, bağlantı işçileri, FileWriter (`pwrite`), AIMD hız denetleyicisi, hız sınırlayıcı.
- **`KodizStore`**: GRDB modelleri, SQLite WAL veritabanı, kontrol noktaları ve göçler.
- **`KodizBridgeProtocol`**: Tarayıcı eklentisi, Native Host ve App arasındaki IPC protokolü ve Unix domain socket sunucusu.
- **`KodizMedia`**: yt-dlp çalıştırıcı, ilerleme ayrıştırıcı ve Netscape çerez dışa aktarıcısı.
- **`KodizSystem`**: Oturum açılış öğesi (`SMAppService`), uyku engeli (`IOPMAssertion`), `NWPathMonitor`, karantina xattr'ları.

---

## 🛠️ Geliştirme ve Derleme

### Ortam Gereksinimleri
- macOS 14.0 (Sonoma) veya üzeri
- Xcode 16+ (Swift 6.0+)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Node.js 20+

> [!IMPORTANT]
> Sistemde Command Line Tools varsayılan seçiliyse XCTest hatasını önlemek için komutların başına `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` ekleyin.
> Proje masaüstünde veya iCloud sürücüsündeyse derleme önbelleğini dışarıda tutmak için `--scratch-path /tmp/...` ve `-derivedDataPath /tmp/...` kullanın.

### Testleri Çalıştırma
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
swift test --package-path Packages/KodizKit --scratch-path /tmp/kodiz-kk-build
```

### Xcode Projesini Oluşturma ve Derleme
```bash
xcodegen generate

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project KodizDownloadManager.xcodeproj \
           -scheme "Kodiz Download Manager" \
           -derivedDataPath /tmp/kodiz-dd \
           build CODE_SIGNING_ALLOWED=NO
```

### Tarayıcı Eklentisini Derleme ve Test Etme
```bash
cd Extension
npm ci
npm test             # Vitest birim testleri (17 test)
npm run compile      # TypeScript tip denetimi (tsc --noEmit)
npm run build        # Chrome / Chromium MV3
npm run build:firefox # Firefox
npm run build:safari  # Safari
```

---

## 📄 Lisans

Kodiz Download Manager **[PolyForm Noncommercial License 1.0.0](LICENSE)** ile lisanslanmıştır. Kaynak kodu açıktır (kaynak kodu açık, PolyForm Noncommercial), ancak bu bir ticari açık kaynak lisansı değildir:

- **Serbest:** Kişisel kullanım, öğrenme, araştırma, hobi projeleri ve deneme; okullar, üniversiteler, dernekler, vakıflar ve kamu kurumları gibi ticari olmayan kuruluşlar. Bu amaçlarla yazılımı değiştirebilir ve dağıtabilirsiniz.
- **İzne Tabi (Yasak):** Her türlü ticari kullanım, satış, ücretli dağıtım, ticari bir ürüne/hizmete dahil etme veya ticari amaçla yayınlama. Ticari lisans ve izinler için proje sahibiyle iletişime geçin.
- **Atıf Zorunlu:** Yazılımın tamamını veya bir kısmını alan herkes [LICENSE](LICENSE) dosyasındaki `Required Notice:` satırını ve lisans koşullarını korumak zorundadır.

Kullanılan üçüncü taraf bileşenler (`yt-dlp` Unlicense, `QuickJS-ng` MIT, `GRDB` MIT) kendi açık kaynak lisanslarına tabidir.
