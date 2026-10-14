import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        let recorder = Recorder.shared
        recorder.start()
        if let notice = recorder.startupNotice {
            DockPresence.windowWillOpen()
            let alert = NSAlert()
            alert.messageText = "TimeScreen had a problem with its data"
            alert.informativeText = notice
            alert.alertStyle = .warning
            alert.runModal()
            DockPresence.windowDidFinish()
        }
        HotKey.timeline.onPress = { TimelineController.shared.toggle() }
        HotKey.pause.onPress = {
            MainActor.assumeIsolated {
                let recorder = Recorder.shared
                recorder.setRecording(!recorder.isRecording)
                NSSound(named: recorder.isRecording ? "Tink" : "Pop")?.play()
            }
        }
        HotKey.star.onPress = {
            Task { @MainActor in
                let starred = await Recorder.shared.starLatestFrame()
                NSSound(named: starred ? "Glass" : "Basso")?.play()
            }
        }
        HotKey.timeline.registerFromPrefs()
        HotKey.pause.registerFromPrefs()
        HotKey.star.registerFromPrefs()
        ScrollTrigger.shared.start()
        Summarizer.shared.startAutomatic()
        _ = Updater.shared
        if let flag = CommandLine.arguments.firstIndex(of: "--summarize-day"), CommandLine.arguments.indices.contains(flag + 1) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            if let day = formatter.date(from: CommandLine.arguments[flag + 1]) {
                Summarizer.shared.start(.day(containing: day), title: "Day")
            }
            return
        }
        if CommandLine.arguments.contains("--settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { DockPresence.openSettings() }
        } else if CommandLine.arguments.contains("--timeline") {
            TimelineController.shared.show()
        } else if CommandLine.arguments.contains("--welcome") {
            WelcomeController.shared.show()
        } else {
            Task {
                await WelcomeController.shared.showIfFirstRun()
                if !recorder.hasPermission, UserDefaults.standard.bool(forKey: Prefs.welcomeShown),
                   ProcessInfo.processInfo.environment["TIMESCREEN_DATA_DIR"] == nil { recorder.requestPermission() }
            }
        }
    }
}

@main
struct TimeScreenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var recorder = Recorder.shared

    init() { Prefs.register() }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(recorder: recorder)
        } label: {
            Image(systemName: recorder.menuBarSymbol)
                .accessibilityLabel(recorder.menuBarDescription)
                .help(recorder.menuBarDescription)
                .background(SettingsOpenerHook())
        }

        Settings {
            SettingsView(recorder: recorder)
        }
    }
}

struct MenuContent: View {
    @ObservedObject var recorder: Recorder
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        if !recorder.hasPermission {
            Text("Screen Recording access is needed")
            Button("Grant Access…") { recorder.requestPermission() }
            Divider()
        } else if let error = recorder.lastError {
            Text(error)
            Divider()
        } else {
            Text(status)
            Divider()
        }

        Button("Open Timeline") { TimelineController.shared.show() }
        Button(recorder.isRecording ? "Pause Recording" : "Resume Recording") {
            recorder.setRecording(!recorder.isRecording)
        }
        if recorder.isRecording {
            Menu("Pause For") {
                Button("15 Minutes") { recorder.pause(for: 15 * 60) }
                Button("1 Hour") { recorder.pause(for: 60 * 60) }
                Button("8 Hours") { recorder.pause(for: 8 * 60 * 60) }
            }
        }
        Divider()
        Menu("Delete Recent") {
            Button("Last 5 Minutes…") { confirmDeleteRecent(minutes: 5) }
            Button("Last 15 Minutes…") { confirmDeleteRecent(minutes: 15) }
            Button("Last Hour…") { confirmDeleteRecent(minutes: 60) }
        }
        Button("Star This Moment") {
            Task { @MainActor in NSSound(named: await recorder.starLatestFrame() ? "Glass" : "Basso")?.play() }
        }
        if let version = updater.availableVersion {
            Button("Update Available: \(version)…") { updater.checkForUpdates() }
        } else {
            Button("Check for Updates…") { updater.checkForUpdates() }
        }
        Button("Settings…") { DockPresence.openSettings() }
            .keyboardShortcut(",")
        Button("Quit TimeScreen") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func confirmDeleteRecent(minutes: Int) {
        Task { @MainActor in
            let frames = await recorder.frames(lastMinutes: minutes)
            let span = minutes == 60 ? "hour" : "\(minutes) minutes"
            DockPresence.windowWillOpen()
            let alert = NSAlert()
            if frames.isEmpty {
                alert.messageText = "Nothing to delete"
                alert.informativeText = "No screenshots were captured in the last \(span)."
                alert.addButton(withTitle: "OK")
            } else {
                alert.messageText = "Delete the last \(span)?"
                alert.informativeText = "\(frames.count) \(frames.count == 1 ? "screenshot" : "screenshots") and their search text will be removed. This can't be undone."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Delete").hasDestructiveAction = true
                alert.addButton(withTitle: "Cancel")
            }
            let response = alert.runModal()
            if !frames.isEmpty, response == .alertFirstButtonReturn { await recorder.delete(frames) }
            DockPresence.windowDidFinish()
        }
    }

    private var status: String {
        guard recorder.isRecording else {
            guard let until = recorder.pausedUntil else { return "Paused" }
            return "Paused until \(until.formatted(date: .omitted, time: .shortened))"
        }
        if let reason = recorder.skipReason { return reason.message }
        let count = "\(recorder.framesToday) frames today"
        guard let last = recorder.lastCapture else { return count }
        return "\(count) · last \(last.formatted(date: .omitted, time: .standard))"
    }
}

private struct SettingsOpenerHook: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear.onAppear { DockPresence.openSettingsAction = { openSettings() } }
    }
}
