# Spike 05: YouTube Çözümleme için JS Runtime (QuickJS-ng vs Deno)

## Arka Plan
yt-dlp, YouTube'un n-sig ve player algoritması değişiklikleri nedeniyle harici bir JavaScript çalışma zamanı (JS runtime) gerektirmektedir.

## Karşılaştırma

| Kriter | QuickJS-ng (`qjs`) | Deno (`deno`) |
|---|---|---|
| İkili Boyutu | ~1.3 MB (arm64) | ~38 MB (arm64, sıkıştırılmış zip) |
| Başlama Süresi | < 10 ms | ~50 ms |
| Bellek Ayak İzi | < 8 MB | ~30 MB |
| YouTube n-sig Çözümleme Süresi | ~120 ms | ~90 ms |
| Pakete Dahil Edilme | Evet, varsayılan gömülü | İsteğe bağlı (Ayarlar > Video) |

## Sonuç
Kodiz Download Manager uygulamasının `.app` boyutunu küçük ve taşınabilir tutmak amacıyla **QuickJS-ng** varsayılan olarak paket içine dahil edilir (`Resources/Tools/qjs`). Kullanıcı dilerse Ayarlar > Video sekmesinden Deno runtime'ını tek tıkla indirebilir.
