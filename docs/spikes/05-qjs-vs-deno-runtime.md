# Spike 05: YouTube Çözümleme için JS Runtime (QuickJS-ng vs Deno)

> **Durum:** Kısmen doğrulandı (kanıt: QuickJS-ng v0.17.0 universal binary `fetch-tools.sh` ile arm64 ve x86_64 ikililerinden `lipo -create` ile derlendi, SHA-256 doğrulandı ve smoke test ile çalıştığı DOĞRULANDI; n-sig çözümleme süreleri bu aşamada ölçülmediğinden teorik / beklenen değer olarak etiketlendi).

## Arka Plan
yt-dlp, YouTube'un n-sig ve player algoritması değişiklikleri nedeniyle harici bir JavaScript çalışma zamanı (JS runtime) gerektirmektedir.

## Karşılaştırma

| Kriter | QuickJS-ng (`qjs`) | Deno (`deno`) |
|---|---|---|
| İkili Boyutu | ~2.5 MB (universal arm64+x86_64) | ~38 MB (arm64, sıkıştırılmış zip) |
| Başlama Süresi | < 10 ms (beklenen) | ~50 ms (beklenen) |
| Bellek Ayak İzi | < 8 MB (beklenen) | ~30 MB (beklenen) |
| YouTube n-sig Çözümleme Süresi | ~120 ms (beklenen) | ~90 ms (beklenen) |
| Pakete Dahil Edilme | Evet, varsayılan gömülü (`Resources/Tools/qjs`) | İsteğe bağlı (Ayarlar > Video) |

## Sonuç
Kodiz Download Manager uygulamasının `.app` boyutunu küçük ve taşınabilir tutmak amacıyla **QuickJS-ng** varsayılan olarak paket içine dahil edilir (`Resources/Tools/qjs`).
