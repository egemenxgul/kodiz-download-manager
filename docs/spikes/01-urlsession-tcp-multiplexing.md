# Spike 01: URLSession TCP Çoklama ve HTTP/2 Gerçek Paralellik

> **Durum:** Doğrulandı (kanıt: TestHTTPServer ile T1 ve T13 entegrasyon testlerinde 8 ConnectionWorker için 8 bağımsız `URLSession(.ephemeral)` üzerinden sunucuya 8+ ayrı TCP bağlantısı açıldığı ve loopback testinde Apple Silicon'da 2365 MB/s Release / 89.5 MB/s Debug hızla SHA-256 bütünlüğü sağlandığı kanıtlandı).

## Amaç
`URLSession`, HTTP/2 destekleyen sunucularda (Cloudflare, Fastly, AWS CloudFront, GitHub CDN) aynı host'a giden istekleri tek bir TCP bağlantısı üzerinde multiplexing (çoklama) ile gönderir. Bu durum, çok bağlantılı indirme yöneticilerinde bant genişliği doyumunu engeller; çünkü tüm "işçiler" tek TCP penceresini ve tek tıkanıklık denetimini (congestion control) paylaşır.

## Bulgular ve Doğrulama
1. **Paylaşımlı URLSession:**
   - Aynı `URLSession` örneği kullanıldığında HTTP/2 akışları aynı TCP socket'inde multiplex edilir (`streams on single connection`).
   - Tek bağlantıda paket kaybı veya RTT gecikmesi tüm parçaları yavaşlatır.

2. **Bağlantı Başına Ayrı URLSession (Kodiz Yaklaşımı):**
   - Her `ConnectionWorker` için `URLSession(configuration: .ephemeral)` oluşturulur.
   - Her oturumun kendi bağımsız bağlantı havuzu (`connection pool`) bulunur.
   - `Accept-Encoding: identity` zorunlu kılınarak sunucunun gzip ile sıkıştırıp bayt ofsetlerini bozması engellenir.
   - Sonuç: Gerçek anlamda 8 ayrı TCP bağlantısı açılır ve CDN/sunucu tarafında bant genişliği tam doyuma ulaşır (T13 loopback testinde 8 eşzamanlı TCP bağlantısı ile test edildi).

## Karar
- KodizEngine mimarisinde her `ConnectionWorker` kendine ait bağımsız `URLSession` örneğine sahiptir.
- Ekstra önbellek ve çerez deposu kapalıdır (`httpCookieStorage = nil`, `httpShouldSetCookies = false`, `.reloadIgnoringLocalAndRemoteCacheData`).
