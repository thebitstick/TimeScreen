import CoreGraphics
import Foundation

enum CaptureCadence {
    /// Little changes while nobody is at the Mac, so captures get sparser the longer it has been untouched.
    static func interval(base: TimeInterval, idleSeconds: TimeInterval) -> TimeInterval {
        switch idleSeconds {
        case ..<60: return base
        case ..<300: return max(base, 15)
        default: return max(base, 30)
        }
    }

    static var idleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}
