# mectrics

Hafif, gizli ve modern bir macOS menü çubuğu sistem monitörü.
CPU, Bellek, Pil ve daha fazlasını canlı **sparkline**'larla menü çubuğunda gösterir;
isteğe bağlı canlı floating panel ve WidgetKit widget'ı ile.

> Durum: **v0.1 MVP geliştirme aşamasında** — çekirdek motor (MetricsKit) + menü çubuğu
> uygulaması çalışıyor: CPU / Bellek / Pil, sparkline, detay popover, ayarlar, girişte başlat.

## Konumlandırma
*iStat'ın derinliği + Stats'ın açık ruhu + hepsinden hafif & modern.* Ayrıntı: [`docs/`](docs/).

- [00 — Araştırma](docs/00-research.md)
- [01 — Ürün Planı](docs/01-product-plan.md)
- [02 — Teknik Mimari](docs/02-architecture.md)
- [03 — Yol Haritası](docs/03-roadmap.md)

## Proje yapısı
```
mectrics/
├── docs/                    # ürün & mimari dokümanları
├── project.yml              # XcodeGen proje tanımı (kaynak; .xcodeproj üretilir)
├── Mectrics/                # menü çubuğu uygulaması (SwiftUI + AppKit)
│   ├── App/                 # AppDelegate, AppModel, LoginItem
│   ├── MenuBar/             # NSStatusItem controller + canlı sparkline çizimi
│   ├── UI/                  # popover, sparkline, biçimlendirme
│   └── Settings/            # ayarlar penceresi
└── Packages/MetricsKit/     # UI-bağımsız metrik motoru (SwiftPM)
    ├── Sources/MetricsKit/  # provider'lar, scheduler, store, engine
    ├── Sources/MectricsCLI/ # `swift run mectrics-cli` — terminal demosu
    └── Tests/
```

## Gereksinimler
- macOS 15+ (geliştirme: Xcode 16+/26, Swift 5.10+)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Geliştirme

**Çekirdek motoru terminalde çalıştır (Xcode gerekmez):**
```bash
cd Packages/MetricsKit
swift run mectrics-cli      # canlı CPU/Bellek/Pil
swift test                 # birim testler
```

**Menü çubuğu uygulamasını derle & çalıştır:**
```bash
xcodegen generate          # project.yml -> Mectrics.xcodeproj
open Mectrics.xcodeproj     # Xcode'da Cmd+R
# veya komut satırından:
xcodebuild -project Mectrics.xcodeproj -scheme Mectrics -configuration Debug build
```

## Gizlilik
Sıfır telemetri. Hiçbir kullanım/donanım verisi cihazdan çıkmaz.

## Lisans
Açık kaynak (lisans dağıtım fazında netleşecek — öneri: MIT).
