# 00 — Pazar & Rakip Araştırması

> Amaç: "Usage" tarzı Mac donanım-metrik uygulamalarını incelemek, kullanıcıların bu tür
> apps'lerden beklediği özellikleri çıkarmak ve **mectrics** için farklılaşma alanlarını
> belirlemek.

## 1. İncelenen ürünler

| Ürün | Model | Öne çıkanlar | Zayıf yönler |
|------|-------|--------------|--------------|
| **Usage** (usage.pro) | Paid + Setapp, macOS/iOS/iPadOS | 40+ menu bar bileşeni, "en CPU-dostu" iddiası, iCloud sync, gizlilik odaklı, güzel widget'lar, per-process CPU/RAM | Kapalı kaynak, sensör derinliği iStat kadar değil |
| **Stats** (exelban, açık kaynak) | Ücretsiz, MIT, 25k+ ⭐ | CPU/GPU/RAM/Disk/Network/Sensors/Battery/Bluetooth/Clock, native SwiftUI, düşük kaynak, 40+ dil, çok özelleştirilebilir | UI biraz teknik/yoğun, onboarding zayıf, widget iletişimi varsayılan kapalı (sistem yükü) |
| **iStat Menus** (Bjango) | ~$12–30 tek seferlik | En derin sensör/fan/voltage kapsamı, geçmiş veri, custom sensör, notification threshold, en olgun | **Sparkline yok**, klavye kısayolu yok, popover taşınamaz, dashboard özelleştirmesi kısıtlı, sürüm başı ücretli upgrade, bazı kullanıcılarda **pil tüketimi** şikayeti |
| **MoniThor** | Ücretsiz | Live sparkline, 8 accent renk teması, sürüklenebilir kompakt panel, Apple Silicon-optimize native Swift | Yeni, ekosistem küçük |
| **Stats Panel / Activity Bar / Air Stats** | Freemium | Hafiflik, "sadece CPU/RAM/Network isteyenlere" sade seçenek | Sığ özellik seti |

## 2. Kullanıcıların en çok istediği özellikler (rakip + forum sentezi)

1. **Live sparkline / trend grafiği** — statik sayı değil, son ~60 örneğin mini grafiği (CPU, RAM, network...). iStat'ın en büyük eksiği olarak öne çıkıyor.
2. **Klavye kısayolları** — tam ekran çalışırken fare olmadan paneli açabilme.
3. **Sürüklenebilir / serbest konumlanan panel** — menü çubuğu ikonuna sabitlenmiş popover yerine taşınabilir pencere.
4. **Düşük kaynak tüketimi** — native Swift 30–80 MB; Electron 200–400 MB. Monitörün kendisi pil/CPU yememeli. iStat'ın pil şikayetleri buradan.
5. **Derin ama okunur metrikler** — per-core CPU, memory *pressure* (sadece kullanım değil), network up/down, battery health + cycle count, disk read/write throughput, sıcaklık/fan.
6. **Bildirim eşikleri** — "CPU %90'ı 30 sn geçerse uyar", "pil %20 altına düştü", "disk doldu".
7. **Gizlilik** — hiçbir veri toplanmaması net bir satış argümanı (Usage bunu vurguluyor).
8. **Tema / accent renk** — görsel kişiselleştirme.
9. **Sade varsayılan + derinlik opsiyonel** — yeni kullanıcı boğulmamalı, power-user derinliğe inebilmeli. Stats'ın onboarding zaafı buradan.
10. **Per-process görünüm** — "neyim CPU/RAM yiyor?" hızlı cevabı (mini Activity Monitor).

## 3. Yaygın şikayetler (kaçınılacaklar)

- Menü çubuğu kalabalığı ve okunması zor mikro-grafikler.
- Sürüm başı zorunlu ücretli upgrade (iStat modeli birçok kullanıcıyı Stats'a itiyor).
- Uygulamanın kendisinin pil/CPU tüketmesi (özellikle uyku sırasında ölçmeye devam etmek).
- Karmaşık, rehbersiz ilk kurulum.
- WidgetKit widget'larının gerçek zamanlı olmaması (sistem timeline throttle'ı).

## 4. mectrics için farklılaşma tezi

> **"iStat'ın derinliği + Stats'ın açık ruhu + modern, sade, gerçekten hafif bir deneyim."**

Konumlanma sütunları:
1. **Sparkline-first menü çubuğu** — her modül canlı mini grafik (iStat'ın #1 eksiğini kapat).
2. **İki widget modu** — (a) WidgetKit masaüstü widget'ı (düşük frekans, sistem-native), (b) uygulamanın kendi **canlı floating panel**'i (gerçek zamanlı, sürüklenebilir, always-on-top). Kullanıcı ikisinden birini/ikisini seçer.
3. **Radikal hafiflik** — native SwiftUI/AppKit, uyku/güç kaynağına göre uyarlanan örnekleme frekansı (pilde yavaşla), hedef < 60 MB RAM ve düşük CPU.
4. **Onboarding + akıllı varsayılanlar** — ilk açılışta 3 adımda kurulum; "Basit" ve "Pro" profilleri.
5. **Gizlilik garantisi** — sıfır telemetri, sandbox/hardened runtime, açık gizlilik metni.
6. **Adil fiyatlandırma** — güçlü ücretsiz çekirdek + tek seferlik Pro lisansı (sürüm-başı zorlama yok).

## Kaynaklar
- [Usage — usage.pro](https://usage.pro/)
- [Stats — mac-stats.com](https://mac-stats.com/) / [GitHub exelban/stats](https://github.com/exelban/stats)
- [iStat Menus — bjango.com](https://bjango.com/mac/istatmenus/)
- [MoniThor — best menu bar apps guide](https://monithor.dev/guides/best-mac-menu-bar-apps)
- [Setapp — best Mac monitoring software](https://setapp.com/app-reviews/best-mac-monitoring-software)
- [MacRumors — iStat Menus battery drain thread](https://forums.macrumors.com/threads/istat-menus-battery-drain-issue.2265412/)
