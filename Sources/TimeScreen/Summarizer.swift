import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum SummaryAvailability: Equatable {
    case available
    case unavailable(String)

    var message: String? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

/// Apple's on-device language model. Nothing is sent anywhere, and the cloud model that macOS 27 also offers is deliberately not used.
enum SystemModel {
    static var availability: SummaryAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return .unavailable("This Mac doesn't support Apple Intelligence.")
                case .appleIntelligenceNotEnabled: return .unavailable("Turn on Apple Intelligence in System Settings to write summaries.")
                case .modelNotReady: return .unavailable("Apple's on-device model is still downloading or getting ready. Try again in a while.")
                @unknown default: return .unavailable("Apple's on-device model isn't available right now.")
                }
            }
        }
        return .unavailable("Summaries need macOS 26 or later.")
        #else
        return .unavailable("This build of TimeScreen was made without support for Apple's on-device model.")
        #endif
    }

    static func makeGenerator() -> TextGenerator? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), availability == .available { return SystemModelGenerator() }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
struct SystemModelGenerator: TextGenerator {
    var contextSize: Int { SystemLanguageModel.default.contextSize }

    func tokenCount(_ text: String) async -> Int {
        if #available(macOS 26.4, *), let count = try? await SystemLanguageModel.default.tokenCount(for: text) { return count }
        return Int(Double(text.count) / 2.8) + 1
    }

    func generate(instructions: String, prompt: String, maxTokens: Int) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt, options: GenerationOptions(maximumResponseTokens: maxTokens))
        return response.content
    }
}
#endif

/// Runs one summary job at a time for the interface, and optionally writes summaries of finished blocks while the Mac is idle and
/// plugged in.
@MainActor
final class Summarizer: ObservableObject {
    static let shared = Summarizer()

    struct Job: Equatable {
        let window: SummaryWindow
        var title: String
        var done: Int
        var total: Int
    }

    @Published private(set) var availability = SystemModel.availability
    @Published private(set) var job: Job?
    @Published private(set) var errors: [SummaryWindow: String] = [:]
    @Published private(set) var revision = 0

    private var task: Task<Void, Never>?
    private var automaticTask: Task<Void, Never>?
    private var skippedAutomatically = Set<SummaryWindow>()

    func refreshAvailability() { availability = SystemModel.availability }

    func start(_ window: SummaryWindow, title: String, regenerate: Bool = false) {
        guard job == nil else { return }
        errors[window] = nil
        refreshAvailability()
        guard let generator = SystemModel.makeGenerator() else {
            errors[window] = availability.message ?? "Summaries aren't available."
            return
        }
        let service = SummaryService(db: Recorder.shared.db, generator: generator)
        job = Job(window: window, title: title, done: 0, total: 1)
        let owner = self
        task = Task {
            do {
                _ = try await service.summarize(window, regenerate: regenerate) { done, total in
                    Task { @MainActor in
                        owner.job?.done = done
                        owner.job?.total = total
                    }
                }
            } catch is CancellationError {
            } catch {
                owner.errors[window] = error.localizedDescription
            }
            owner.job = nil
            owner.revision += 1
        }
    }

    func cancel() { task?.cancel() }

    func pendingCount(_ window: SummaryWindow) async -> Int {
        guard let generator = SystemModel.makeGenerator() else { return 0 }
        return (try? await SummaryService(db: Recorder.shared.db, generator: generator).pendingCount(window)) ?? 0
    }

    func clearErrors() { errors = [:] }

    func deleteAll() async {
        try? await Recorder.shared.db.deleteAllSummaries()
        skippedAutomatically = []
        revision += 1
    }

    // MARK: Automatic summaries

    func startAutomatic() {
        guard automaticTask == nil else { return }
        automaticTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                await self?.automaticPass()
            }
        }
    }

    private func automaticPass() async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Prefs.autoSummaries), job == nil, !Power.isOnBattery,
              !ProcessInfo.processInfo.isLowPowerModeEnabled, CaptureCadence.idleSeconds >= 60,
              let generator = SystemModel.makeGenerator() else { return }
        let db = Recorder.shared.db
        let service = SummaryService(db: db, generator: generator)
        let now = Date()
        let from = Calendar.current.date(byAdding: .hour, value: -36, to: now) ?? now
        guard let starts = try? await db.blockStarts(from: from, to: now) else { return }
        var written = 0
        for start in starts where written < 3 {
            let window = SummaryWindow.block(containing: start)
            guard window.end <= now.addingTimeInterval(-60), !skippedAutomatically.contains(window),
                  CaptureCadence.idleSeconds >= 60 else { continue }
            guard ((try? await service.pendingCount(window)) ?? 0) > 0 else { continue }
            do {
                _ = try await service.summarize(window)
                written += 1
            } catch {
                skippedAutomatically.insert(window)
            }
        }
        if written > 0 { revision += 1 }
    }
}
