# 03 — Yol Haritası & Geliştirme Planı

> Sen macOS'a yenisin; bu yüzden plan "önce çalışan en küçük dikey dilim" mantığında.
> Her fazın sonunda **çalışan, elle görülebilen** bir şey var.

## 0. Ön koşullar (senin / benim yapacaklarım)
| # | İş | Kim |
|---|----|-----|
| 0.1 | Xcode kurulu (App Store) + Command Line Tools | Sen (bir kez) |
| 0.2 | Apple Developer hesabı ($99/yıl) — notarization & dağıtım için gerekli | **Sen** (karar + ödeme) |
| 0.3 | Proje iskeleti, MetricsKit paketi, ilk kod | Ben |
| 0.4 | Bundle ID, App Group ID belirleme (ör. `com.mectrics.app`) | Beraber (ben öneririm) |

> Not: Geliştirme ve yerel çalıştırma için Developer hesabı **gerekmez** (kendi Mac'inde
> imzasız/geçici imzayla çalışır). Hesap yalnızca **dağıtım/notarization** aşamasında şart.

---

## Faz 1 — MVP (v0.1): "Menü çubuğunda canlı CPU/RAM/Pil"
**Hedef:** Uygulama açılıyor, menü çubuğunda CPU %, RAM %, Pil % + sparkline; tıklayınca detay popover; ayarlardan modül aç/kapat; login'de başlat.

- [ ] Xcode workspace + ana app target + `MetricsKit` SPM paketi.
- [ ] `SamplingScheduler` + `MetricStore` (ring buffer).
- [ ] Provider'lar: **CPU** (`host_processor_info`), **Memory** (`host_statistics64`), **Battery** (IOKit IOPS).
- [ ] `MenuBarController` + custom `NSView` (sayı + sparkline çizimi).
- [ ] Modül detay popover (SwiftUI).
- [ ] Ayarlar penceresi (SwiftUI): modül aç/kapat, örnekleme frekansı.
- [ ] `SMAppService` ile launch-at-login.
- [ ] Adaptif örnekleme (AC/pil).
- **Çıktı:** Kendi Mac'inde çalışan gerçek monitör. İlk "wow".

## Faz 2 — Çekirdek genişleme (v0.5)
**Hedef:** Free çekirdeğin tamamı + deneyim özellikleri.
- [ ] Provider'lar: **Network** (getifaddrs Δ), **Disk** (statfs + throughput), **Bluetooth** (IORegistry pil), **Clock**.
- [ ] **Floating panel** (NSPanel canlı widget) — sürüklenebilir, always-on-top.
- [ ] **Onboarding** (3 adım: profil / modül / izin).
- [ ] **Temalar & accent**, compact/normal menü çubuğu modu.
- [ ] **Bildirim eşikleri** (temel kurallar).
- [ ] **Global hotkey** (panel aç/kapat).
- **Çıktı:** Günlük kullanılabilir, "beta'ya hazır" ürün.

## Faz 3 — İleri modüller & dağıtım (v1.0)
**Hedef:** Donanım modülleri, widget, açık kaynak yayını, DMG dağıtımı.
- [ ] Provider'lar: **GPU**, **Sensörler/Sıcaklık (SMC)**, **Fanlar (SMC)** — Apple Silicon (+ mümkünse Intel) test.
- [ ] **WidgetKit extension** (small/medium/large, App Group snapshot).
- [ ] Gelişmiş bildirimler, veri geçmişi/export.
- [ ] **Hardened Runtime + notarization**, **Sparkle** oto-güncelleme, DMG paketleme.
- [ ] GitHub repo (açık kaynak, LICENSE), README, landing/gizlilik metni, GitHub Releases.
- **Çıktı:** Halka açık, açık kaynak v1.0.

## Faz 4 — v1.x+ (sonra)
- Per-process gelişmiş görünüm (mini Activity Monitor).
- App Store sürümü (sensör-kısıtlı).
- iOS/iPad companion + iCloud sync.
- Yerelleştirme (çoklu dil).

---

## Verilen kararlar ✅
1. **Dağıtım:** **Direct / DMG** (Developer ID + notarization). Apple Developer hesabı mevcut. Tam sensör/GPU/fan erişimi (sandbox kısıtı yok).
2. **Min macOS:** **15 Sequoia** (geliştirme makinesi macOS 27 / Xcode 26 / Swift 6.3, Apple Silicon).
3. **Monetizasyon:** **Tamamen ücretsiz & açık kaynak.** Free/Pro ayrımı ve lisanslama kodu yok → mimari basitleşir.

## Hâlâ netleşecek (küçük)
- **Açık kaynak lisansı:** MIT (izin verici) vs GPLv3 (Stats gibi, türevleri açık tutar). → Öneri: başlangıçta **MIT** (esneklik), istenirse değişir.
- **Bundle ID / marka:** `com.mectrics.app` (öneri). İsim "mectrics" kesin varsayılıyor.
- **GitHub org/repo adı** ve Sponsors (opsiyonel) kurulumu — dağıtım fazında.

## Riskler & azaltma
| Risk | Azaltma |
|------|---------|
| SMC/GPU key'leri Apple Silicon'da farklı, kırılgan | Stats açık kaynağını referans al; donanım matrisinde test; sensörleri Pro/opsiyonel tut. |
| App Store sandbox sensörleri engeller | Önce Direct dağıtım; App Store'u ayrı, kısıtlı SKU olarak sonra. |
| Uygulamanın kendisi pil/CPU yer (iStat şikayeti) | Adaptif örnekleme + görünürlük-farkında redraw baştan mimaride. |
| WidgetKit gerçek zamanlı değil beklentisi | Floating panel'i "canlı widget" olarak öne çıkar; WidgetKit'i "özet" olarak konumla. |
| Notarization/imza yeni bir alan (sana) | Ben script'leyeceğim; sadece Developer hesabı + bir kez sertifika kurulumu senden. |

## Şimdi ne yapıyoruz?
Faz 1'e başlıyorum: proje iskeleti + `MetricsKit` + ilk CPU provider. Yukarıdaki 5 kararı
netleştirmek işi hızlandırır ama **beklemeden** makul varsayılanlarla (Direct dağıtım,
macOS 14, tek-seferlik Pro, `com.mectrics.app`) MVP koduna başlayabilirim.
