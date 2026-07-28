# 02 — Teknik Mimari: mectrics

> Not: Sen web/mobil geliştirmeye hakimsin ama macOS'a yenisin. Bu doküman kararların
> *neden*ini de açıklar; macOS'a özgü tuzakları işaretler.

## 1. Teknoloji seçimleri (ve gerekçeleri)

| Katman | Seçim | Neden |
|--------|-------|-------|
| Dil | **Swift 5.9+** | Native, düşük kaynak; ekosistem standardı. |
| UI | **SwiftUI + AppKit hibrit** | SwiftUI: settings/popover/paneller (hızlı, modern). AppKit (`NSStatusItem`): menü çubuğunda canlı sparkline çizmek için tam kontrol gerekiyor — saf SwiftUI `MenuBarExtra` custom çizimde kısıtlı. |
| Menü çubuğu | **`NSStatusItem` + custom `NSView`** (AppKit), popover içi SwiftUI | Canlı metin+sparkline render, ⌘-drag ile sıralama, hassas genişlik kontrolü. |
| Widget | **WidgetKit** extension + kendi **floating `NSPanel`** | WidgetKit = sistem-native ama throttled (dk mertebesi). Floating panel = gerçek zamanlı canlı widget. İkisi de sunulur. |
| Metrik motoru | **Local Swift Package `MetricsKit`** | Test edilebilir, UI'dan bağımsız, widget extension ile paylaşılabilir. |
| Paylaşım | **App Group + shared container** | Ana app ↔ widget extension veri paylaşımı. |
| Reaktivite | **Combine / `@Observable`** | Sampler → store → ViewModel → UI akışı. |
| Kalıcılık | **UserDefaults (App Group)** + küçük JSON snapshot | Ayarlar + widget için son snapshot. Ağır DB gereksiz. |
| Güncelleme | **Sparkle** (direct dağıtımda) | Standart macOS otomatik güncelleme. |
| Global hotkey | **`KeyboardShortcuts` (sindresorhus)** veya Carbon `RegisterEventHotKey` | Panel aç/kapat. |
| Login item | **`SMAppService`** (macOS 13+) | Modern launch-at-login API. |
| Lisans | **Lemon Squeezy / Paddle** + lokal doğrulama | Solo-friendly, KDV/vergi hallediyor. |

**Min hedef:** **macOS 15 Sequoia** (karar verildi). Geliştirme makinesi: macOS 27 / Xcode 26.6 / Swift 6.3 / Apple Silicon. Modern API'lar (`@Observable`, güncel WidgetKit) rahatça kullanılır.

**Not (açık kaynak / ücretsiz kararı):** Free/Pro ayrımı ve lisanslama kodu **yok**. `Licensing/` klasörü ve lisans doğrulama mimariden çıkarıldı; tüm modüller herkese açık.

---

## 2. Yüksek seviye mimari

```
┌──────────────────────────────────────────────────────────────┐
│                     Mectrics.app (main)                       │
│                                                              │
│  AppDelegate ── MenuBarController (NSStatusItem'lar)          │
│       │              │                                        │
│       │              ├── CPUStatusItem  (NSView: text+spark)  │
│       │              ├── MemStatusItem                        │
│       │              └── ...                                  │
│       │                                                       │
│       ├── PopoverManager (SwiftUI detay görünümleri)          │
│       ├── FloatingPanelManager (NSPanel canlı widget'lar)     │
│       ├── SettingsWindow (SwiftUI)                            │
│       └── NotificationEngine (eşik kuralları)                 │
│                          ▲                                     │
│                          │ @Observable / Combine              │
│  ┌───────────────────────┴──────────────────────────────┐    │
│  │                MetricsKit (Swift Package)             │    │
│  │                                                      │    │
│  │  SamplingScheduler (adaptif timer)                   │    │
│  │      → fan-out →                                     │    │
│  │  [MetricProvider]  CPU / Memory / Battery /          │    │
│  │                    Network / Disk / GPU / Sensors /  │    │
│  │                    Fans / Bluetooth                  │    │
│  │      → yazar →                                       │    │
│  │  MetricStore (per-metric ring buffer + son değer)    │    │
│  │      → snapshot →                                    │    │
│  │  SharedSnapshotWriter (App Group container)          │    │
│  └──────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────┘
              │ App Group (shared UserDefaults + JSON)
              ▼
┌──────────────────────────────────────────────────────────────┐
│   MectricsWidget (WidgetKit extension)                        │
│   TimelineProvider → SharedSnapshotReader → SwiftUI views     │
└──────────────────────────────────────────────────────────────┘
```

---

## 3. MetricsKit tasarımı (çekirdek)

```swift
// Bir örnek ölçüm
struct MetricSample {
    let timestamp: Date
    let value: Double          // normalize edilmiş temel değer (ör. CPU %)
    let detail: [String: Double] // per-core, used/wired, up/down vb.
}

protocol MetricProvider: AnyObject {
    var id: MetricID { get }          // .cpu, .memory, ...
    var isAvailable: Bool { get }     // donanım/izin var mı
    var cost: SamplingCost { get }    // light/medium/heavy → zamanlama
    func sample() throws -> MetricSample
}

final class MetricStore {
    // metric başına sabit boyutlu ring buffer (ör. 300 örnek = ~5 dk @1s)
    func append(_ s: MetricSample, for id: MetricID)
    func latest(_ id: MetricID) -> MetricSample?
    func history(_ id: MetricID, count: Int) -> [MetricSample]  // sparkline için
}

final class SamplingScheduler {
    // Adaptif: AC'de 1s, pilde 2–3s, uykuda/ekran kapalıyken duraklat.
    // Ağır provider'lar (sensör/SMC) daha seyrek örneklenir.
}
```

### Ölçüm kaynakları (macOS API haritası)
| Metrik | API / kaynak | Not / tuzak |
|--------|--------------|-------------|
| CPU | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` / `host_statistics64` | Ardışık iki örnek farkı = kullanım. Per-core buradan. |
| Bellek | `host_statistics64(vm_statistics64)` + `sysctl(hw.memsize)` | pressure için `vm.memory_pressure` / compressed sayfalar. |
| Pil | **IOKit** `IOPSCopyPowerSourcesInfo`, `IOPSCopyPowerSourcesList`; health/cycle için `IORegistry AppleSmartBattery` | cycle count IORegistry'den. |
| Ağ | `getifaddrs` + `if_data` (ibytes/obytes) veya `sysctl net.route` | Δbytes/Δt = hız. Per-process için `nettop`/`libnetstat` (Pro, daha zor). |
| Disk (alan) | `statfs` / `URL.resourceValues(.volumeAvailableCapacity...)` | Basit. |
| Disk (throughput) | **IOKit** `IOBlockStorageDriver` istatistikleri | Δ okuma/yazma bytes. |
| GPU | **IOKit** `IOAccelerator`/`AGXAccelerator` "Device Utilization %"; VRAM `Metal`/IORegistry | Apple Silicon'da anahtarlar farklı; test gerektirir. |
| Sensör/Sıcaklık | **SMC** (`AppleSMC`) key okuma; Apple Silicon'da `IOHIDEventSystemClient` thermal sensörleri | SMC key seti M-serisinde farklı. Stats kod tabanı iyi referans. |
| Fan | **SMC** `F0Ac...` keyleri | Bazı Mac'lerde fan yok (fanless MacBook Air). |
| Bluetooth | **IOBluetooth** / `IORegistry` cihaz pil `BatteryPercent` | AirPods vb. |

> **Önemli:** Sensör/SMC/fan/GPU okuma App Store sandbox'ında kısıtlı olabilir. Bu yüzden
> tam özellik için **Developer ID + notarization ile direct dağıtım** (Stats/iStat modeli)
> öneriyoruz; App Store sürümü sensör-kısıtlı olabilir. Karar `03-roadmap.md`'de.

---

## 4. Menü çubuğu render'ı (kritik detay)

- Modül başına bir `NSStatusItem` (kullanıcı hangi modülleri göstereceğini seçer).
- Her item bir custom `NSView` barındırır: sol tarafta sayı/ikon, sağda opsiyonel sparkline (`CAShapeLayer` veya `draw(_:)`).
- Redraw: `MetricStore` güncellendiğinde (Combine subscription), ~1–2 sn'de bir. Görünür değilken (menü bar gizli/tam ekran) redraw'ı kıs.
- ⌘-drag ile yeniden sıralama macOS'un doğal davranışı — `NSStatusItem.autosaveName` ile konum korunur.
- Genişlik: içeriğe göre dinamik; "compact/normal" moduna göre sparkline gizlenir.

## 5. Floating panel (canlı widget)
- `NSPanel` (nonactivating, `.floating` veya `.statusBar` level), köşe yuvarlatılmış, saydam blur (`NSVisualEffectView`).
- İçerik SwiftUI (`NSHostingView`), `MetricStore`'a bağlı — gerçek zamanlı.
- Sürükle-bırak konum, ekranda snap, "always on top" toggle, boyut preset'leri.
- Çoklu panel (Pro): her biri farklı modül.

## 6. WidgetKit extension
- `TimelineProvider` App Group'tan son snapshot'ı okur (`SharedSnapshotReader`).
- Ana app periyodik olarak `SharedSnapshotWriter` ile snapshot + kısa geçmiş yazar; `WidgetCenter.shared.reloadTimelines` ile tetikler.
- **Kısıt:** sistem güncelleme sıklığını throttle eder (gerçek zamanlı değil, dk mertebesi). Kullanıcıya bu net anlatılır; gerçek zaman isteyen floating panel'i kullanır.
- Small/Medium/Large; Lock Screen/Notification Center.

## 7. Güç & performans stratejisi (farklılaşma sözü)
- **Adaptif örnekleme:** AC 1s / pil 2–3s / ekran kapalı-uyku duraklat.
- Ağır provider'ları (SMC, GPU) seyrek örnekle; sadece ilgili UI görünürken hızlandır.
- Görünmeyen UI'ı hesaplama dışı bırak (menü bar gizli, panel kapalı).
- Zero-alloc hot path: ring buffer önceden ayrılmış; her örnekte heap allocation'dan kaçın.
- Hedef: Activity Monitor'da "Energy Impact: Low", RAM < 60 MB.

## 8. Güvenlik / gizlilik / dağıtım
- **Sıfır telemetri**, ağ çağrısı yalnızca (opsiyonel) güncelleme ve lisans doğrulama.
- **Hardened Runtime** + **notarization** (direct dağıtım).
- Sandbox: App Store sürümünde zorunlu → sensör modülleri kısıtlı olabilir; direct sürüm non-sandbox veya minimal entitlement.
- Gerekli entitlement/izinler onboarding'de şeffaf istenir.

## 9. Test stratejisi
- `MetricsKit` unit test (provider'lar mock host verisiyle; hesaplama doğruluğu — Δbytes/Δt, CPU %).
- Snapshot/golden test SwiftUI görünümleri.
- Manuel matris: Intel + Apple Silicon (M-serisi), fansız Air, harici monitör, düşük pil.
- Performans: uzun süreli çalışmada RAM/CPU regresyon takibi.

## 10. Repo yapısı
```
mectrics/
├── docs/                         # bu planlar
├── Mectrics.xcodeproj            # (veya Tuist/XcodeGen ile üretilir)
├── Mectrics/                     # ana app target
│   ├── App/                      # AppDelegate, MectricsApp, Settings scene
│   ├── MenuBar/                  # NSStatusItem controller + custom NSView'lar
│   ├── Panels/                   # FloatingPanelManager, SwiftUI panel görünümleri
│   ├── Popover/                  # modül detay görünümleri
│   ├── Settings/                 # ayarlar UI
│   ├── Notifications/            # NotificationEngine
│   ├── Licensing/                # Pro lisans doğrulama
│   └── Resources/                # Assets, Info.plist, entitlements
├── MectricsWidget/               # WidgetKit extension target
├── Packages/
│   └── MetricsKit/               # SPM: providers, scheduler, store, shared IO
│       ├── Sources/MetricsKit/
│       └── Tests/MetricsKitTests/
└── Tools/                        # scriptler (notarize, release)
```
> Başlangıçta Xcode projesi doğrudan (yeni başlayan için en az sürtünme). Metrik mantığı
> baştan `MetricsKit` paketinde → test edilebilir ve widget ile paylaşılabilir.
