import AppKit
import MetricsKit

/// Uygulama yaşam döngüsü + menü çubuğu kurulumu.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var menuBar: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menü çubuğu ajanı: Dock ikonu yok.
        NSApp.setActivationPolicy(.accessory)

        menuBar = MenuBarController(model: model)
        menuBar.rebuild()

        // Modül seçimi değişince menü çubuğunu yeniden kur.
        model.onModulesChanged = { [weak self] in
            self?.menuBar.rebuild()
        }

        // Her örnekleme döngüsünde (ana thread) modeli ve menü çubuğunu güncelle.
        model.engine.onCycle = { [weak self] updated in
            guard let self else { return }
            for (id, sample) in updated {
                self.model.latest[id] = sample
            }
            self.menuBar.refresh()
        }

        // Enerji dostu: pilde daha yavaş örnekle.
        let onBattery = Self.isOnBattery()
        model.engine.start(onBattery: onBattery)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.engine.stop()
    }

    /// Şu an pil gücünde miyiz? (İlk aralık kararı için basit kontrol.)
    private static func isOnBattery() -> Bool {
        guard let sample = BatteryProvider().sample() else { return false }
        return (sample.detail["charging"] ?? 0) == 0
    }
}
