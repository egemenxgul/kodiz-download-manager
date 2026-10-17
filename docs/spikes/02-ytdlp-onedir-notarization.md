# Spike 02: yt-dlp onedir İmzalama ve Notarization

## Amaç
PyInstaller ile paketlenen yt-dlp'nin macOS Notarization kurallarına tam uyumlu şekilde Developer ID ile imzalanmasını doğrulamak. Tek dosyalık PyInstaller çalıştırılabilirleri her açılışta `/tmp` altına kendini açarak 1-2 saniyelik gecikme yaratır. `onedir` yapısı ise doğrudan yerel kütüphaneleri çalıştırır.

## İmzalama Sırası (İçten Dışa)
Apple Hardened Runtime ve Notary Service için `--deep` bayrağı kullanılması güvenli değildir. İçten dışa doğru sırayla imza atılmalıdır:
1. `Resources/Tools/yt-dlp/**/*.dylib` ve `**/*.so`
2. `Resources/Tools/yt-dlp/yt-dlp` (ana ikili)
3. `Resources/Tools/ffmpeg`, `Resources/Tools/ffprobe`
4. `Resources/Tools/qjs`
5. `Helpers/kodiz-nmh`
6. `PlugIns/KodizSafari.appex`
7. Ana `Kodiz Download Manager.app`

## Entitlement'lar
- Ana uygulama: Hardened Runtime aktif, `com.apple.security.application-groups` aktif.
- Sandboxed App Store kurallarına tabi olunmadığı için `fork`/`exec` serbesttir.
- Notarization işlemi `xcrun notarytool submit` ile başarıyla tamamlanır.
