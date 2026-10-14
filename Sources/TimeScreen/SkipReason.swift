import Foundation
import IOKit.ps

enum SkipReason: Equatable {
    case privateWindow, onBattery, lowPowerMode, diskAlmostFull

    var message: String {
        switch self {
        case .privateWindow: "Not recording: private window open"
        case .onBattery: "Not recording: on battery power"
        case .lowPowerMode: "Not recording: Low Power Mode is on"
        case .diskAlmostFull: "Not recording: the disk is almost full"
        }
    }

    var symbol: String {
        switch self {
        case .privateWindow: "eye.slash.circle"
        case .onBattery, .lowPowerMode: "bolt.slash.circle"
        case .diskAlmostFull: "externaldrive.badge.exclamationmark"
        }
    }

    static func power(onBattery: Bool, lowPower: Bool, pauseOnBattery: Bool, pauseInLowPower: Bool) -> SkipReason? {
        if pauseInLowPower && lowPower { return .lowPowerMode }
        if pauseOnBattery && onBattery { return .onBattery }
        return nil
    }

    static func disk(freeBytes: Int64, minimum: Int64 = 1_000_000_000) -> SkipReason? {
        freeBytes < minimum ? .diskAlmostFull : nil
    }
}

enum Power {
    static var isOnBattery: Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeRetainedValue() as String? else { return false }
        return source == kIOPSBatteryPowerValue
    }
}

enum Disk {
    static func freeBytes(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? Int64.max
    }
}
