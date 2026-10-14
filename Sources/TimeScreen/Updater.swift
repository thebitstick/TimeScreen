import AppKit
import Sparkle

final class Updater: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    static let shared = Updater()

    @Published private(set) var availableVersion: String?
    private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
    }

    static var isDevelopmentBuild: Bool {
        Bundle.main.object(forInfoDictionaryKey: "TimeScreenDevBuild") as? Bool == true
    }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        DockPresence.windowWillOpen()
        controller.checkForUpdates(nil)
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate { publish(update.displayVersionString) }
    }

    func standardUserDriverWillFinishUpdateSession() {
        publish(nil)
    }

    private func publish(_ version: String?) {
        DispatchQueue.main.async { self.availableVersion = version }
    }
}
