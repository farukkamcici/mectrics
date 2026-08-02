import Foundation
import IOKit.ps

/// The power source currently supplying the Mac.
public enum SystemPowerSource {
    /// A fully charged Mac connected to AC remains on AC; charging state is not used.
    public static var isOnBattery: Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sourceType = IOPSGetProvidingPowerSourceType(snapshot)?
                  .takeUnretainedValue()
        else { return false }
        return sourceType as String == kIOPSBatteryPowerValue
    }
}
