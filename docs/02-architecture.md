# 02 — Technical Architecture: mectrics

> Note: you are experienced with web/mobile but new to macOS. This doc explains the *why*
> behind decisions and flags macOS-specific pitfalls.

## 1. Technology choices (and rationale)

| Layer | Choice | Why |
|-------|--------|-----|
| Language | **Swift 5.9+** | Native, low resource use; ecosystem standard. |
| UI | **SwiftUI + AppKit hybrid** | SwiftUI: settings/popover/panels (fast, modern). AppKit (`NSStatusItem`): needed to draw a live sparkline in the menu bar — pure SwiftUI `MenuBarExtra` is limited for custom drawing. |
| Menu bar | **`NSStatusItem` + custom `NSView`**, SwiftUI inside the popover | Live text+sparkline render, ⌘-drag reordering, precise width control. |
| Widget | **WidgetKit** extension + own **floating `NSPanel`** | WidgetKit = system-native but throttled (minutes). Floating panel = real-time live widget. Both are offered. |
| Metric engine | **Local Swift Package `MetricsKit`** | Testable, UI-independent, shareable with the widget extension. |
| Sharing | **App Group + shared container** | Main app ↔ widget extension data sharing. |
| Reactivity | **Combine / `@Observable`** | sampler → store → view model → UI flow. |
| Persistence | **UserDefaults (App Group)** + small JSON snapshot | Settings + last snapshot for the widget. No heavy DB needed. |
| Updates | **Sparkle** (direct distribution) | Standard macOS auto-update. |
| Global hotkey | **`KeyboardShortcuts` (sindresorhus)** or Carbon `RegisterEventHotKey` | Show/hide the panel. |
| Login item | **`SMAppService`** (macOS 13+) | Modern launch-at-login API. |

**Minimum target:** **macOS 15 Sequoia** (decided). Dev machine: macOS 27 / Xcode 26.6 /
Swift 6.3 / Apple Silicon. Modern APIs (`@Observable`, current WidgetKit) are freely usable.

**Note (open-source / free decision):** there is **no** Free/Pro split and **no** licensing
code. The `Licensing/` folder and license verification were removed from the architecture;
all modules are available to everyone.

---

## 2. High-level architecture

```
┌──────────────────────────────────────────────────────────────┐
│                     Mectrics.app (main)                       │
│                                                              │
│  AppDelegate ── MenuBarController (NSStatusItems)            │
│       │              │                                        │
│       │              ├── CPU status item  (NSImage: text+spark)│
│       │              ├── Memory status item                   │
│       │              └── ...                                  │
│       │                                                       │
│       ├── PopoverManager (SwiftUI detail views)              │
│       ├── FloatingPanelManager (NSPanel live widgets)        │
│       ├── SettingsWindow (SwiftUI)                           │
│       └── NotificationEngine (threshold rules)               │
│                          ▲                                     │
│                          │ @Observable / Combine              │
│  ┌───────────────────────┴──────────────────────────────┐    │
│  │                MetricsKit (Swift Package)             │    │
│  │                                                      │    │
│  │  SamplingScheduler (adaptive timer)                  │    │
│  │      → fan-out →                                     │    │
│  │  [MetricProvider]  CPU / Memory / Battery /          │    │
│  │                    Network / Disk / GPU / Sensors /  │    │
│  │                    Fans / Bluetooth                  │    │
│  │      → writes →                                      │    │
│  │  MetricStore (per-metric ring buffer + latest)       │    │
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

## 3. MetricsKit design (the core)

```swift
// A single measurement
struct MetricSample {
    let timestamp: Date
    let value: Double          // normalized base value (e.g. CPU %)
    let detail: [String: Double] // per-core, used/wired, up/down, etc.
}

protocol MetricProvider: AnyObject {
    var id: MetricID { get }          // .cpu, .memory, ...
    var isAvailable: Bool { get }     // hardware/permission present?
    var cost: SamplingCost { get }    // light/medium/heavy → scheduling
    func sample() -> MetricSample?
}

final class MetricStore {
    // fixed-size ring buffer per metric (e.g. 300 samples ≈ 5 min @1s)
    func append(_ s: MetricSample, for id: MetricID)
    func latest(_ id: MetricID) -> MetricSample?
    func history(_ id: MetricID, count: Int) -> [MetricSample]  // for sparklines
}

final class SamplingScheduler {
    // Adaptive: 1s on AC, 2–3s on battery, pause on sleep/screen-off.
    // Heavy providers (sensors/SMC) are sampled less often.
}
```

### Measurement sources (macOS API map)
| Metric | API / source | Note / pitfall |
|--------|--------------|----------------|
| CPU | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` / `host_statistics64` | Diff of two consecutive samples = usage. Per-core from here. |
| Memory | `host_statistics64(vm_statistics64)` + `sysctl(hw.memsize)` | Pressure from `vm.memory_pressure` / compressed pages. |
| Battery | **IOKit** `IOPSCopyPowerSourcesInfo`, `IOPSCopyPowerSourcesList`; health/cycle from `IORegistry AppleSmartBattery` | Cycle count from IORegistry. |
| Network | `getifaddrs` + `if_data` (ibytes/obytes) or `sysctl net.route` | Δbytes/Δt = rate. Per-process via `nettop`/`libnetstat` (harder, later). |
| Disk (space) | `statfs` / `URL.resourceValues(.volumeAvailableCapacity...)` | Simple. |
| Disk (throughput) | **IOKit** `IOBlockStorageDriver` statistics | Δ read/write bytes. |
| GPU | **IOKit** `IOAccelerator`/`AGXAccelerator` "Device Utilization %"; VRAM via `Metal`/IORegistry | Keys differ on Apple Silicon; needs testing. |
| Sensors/Temperature | **SMC** (`AppleSMC`) key reads; on Apple Silicon `IOHIDEventSystemClient` thermal sensors | SMC key set differs on M-series. Stats' code is a good reference. |
| Fans | **SMC** `F0Ac...` keys | Some Macs have no fans (fanless MacBook Air). |
| Bluetooth | **IOBluetooth** / `IORegistry` device `BatteryPercent` | AirPods, etc. |

> **Important:** reading sensors/SMC/fans/GPU may be restricted under the App Store sandbox.
> That's why full functionality favors **direct distribution with Developer ID +
> notarization** (the Stats/iStat model); an App Store build could be sensor-limited.

---

## 4. Menu bar rendering (a critical detail)

- One `NSStatusItem` per module (the user selects which modules to show).
- Each item renders live text + optional sparkline into an `NSImage` assigned to the
  button (avoids subview layout; pixel-precise; correct light/dark adaptation).
- **Width stability:** each module reserves a fixed text width from a worst-case template
  and right-aligns text inside it, so items never shift as values change digit counts.
- Redraw on `MetricStore` updates (~1–2s); throttle when hidden/full-screen.
- ⌘-drag reordering is native; `NSStatusItem.autosaveName` preserves position.

## 5. Floating panel (live widget)
- `NSPanel` (nonactivating, `.floating` level), rounded corners, translucent blur
  (`NSVisualEffectView`).
- SwiftUI content (`NSHostingView`) bound to `MetricStore` — real-time.
- Drag-to-position, screen snap, "always on top" toggle, size presets.
- Multiple panels, each a different module.

## 6. WidgetKit extension
- `TimelineProvider` reads the last snapshot from the App Group (`SharedSnapshotReader`).
- The main app periodically writes a snapshot + short history (`SharedSnapshotWriter`) and
  calls `WidgetCenter.shared.reloadTimelines`.
- **Constraint:** the system throttles update frequency (not real-time). This is explained
  to the user; the floating panel serves the real-time need, WidgetKit serves "at a glance".
- Small/Medium/Large; Lock Screen/Notification Center.

## 7. Power & performance strategy (the differentiation promise)
- **Adaptive sampling:** AC 1s / battery 2–3s / screen-off-sleep pause.
- Sample heavy providers (SMC, GPU) rarely; speed up only when the relevant UI is visible.
- Skip computation for invisible UI (menu bar hidden, panel closed).
- Zero-alloc hot path: the ring buffer is pre-allocated; avoid per-sample heap allocation.
- Target: "Energy Impact: Low", RAM < 60 MB.

## 8. Security / privacy / distribution
- **Zero telemetry**; network calls only for (optional) updates.
- **Hardened Runtime** + **notarization** (direct distribution).
- Sandbox: required for App Store → sensor modules may be limited; the direct build is
  non-sandboxed or minimally entitled.
- Required entitlements/permissions are requested transparently in onboarding.

## 9. Test strategy
- `MetricsKit` unit tests (providers against mock host data; computation correctness —
  Δbytes/Δt, CPU %).
- Snapshot/golden tests for SwiftUI views.
- Manual matrix: Intel + Apple Silicon (M-series), fanless Air, external monitor, low battery.
- Performance: track RAM/CPU regression over long runs.

## 10. Repo structure
```
mectrics/
├── docs/                         # these plans
├── project.yml                   # XcodeGen source (Mectrics.xcodeproj is generated)
├── Mectrics/                     # main app target
│   ├── App/                      # AppDelegate, MectricsApp, Settings scene
│   ├── MenuBar/                  # NSStatusItem controller + custom drawing
│   ├── UI/                       # popover, sparkline, formatting, localization
│   ├── Settings/                 # settings UI
│   └── Resources/                # Localizable.xcstrings, assets
├── Packages/
│   └── MetricsKit/               # SPM: providers, scheduler, store, engine, CLI
│       ├── Sources/MetricsKit/
│       ├── Sources/MectricsCLI/
│       └── Tests/MetricsKitTests/
└── (future) MectricsWidget/      # WidgetKit extension target
```
> Start with the Xcode project directly (least friction for a macOS newcomer). Metric logic
> lives in the `MetricsKit` package from the start → testable and shareable with the widget.
