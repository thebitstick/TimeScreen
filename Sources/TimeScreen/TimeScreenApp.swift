import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        let recorder = Recorder.shared
        recorder.start()
        HotKey.shared.onPress = { TimelineController.shared.toggle() }
        HotKey.shared.registerFromPrefs()
        ScrollTrigger.shared.start()
        _ = Updater.shared
        if CommandLine.arguments.contains("--settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { DockPresence.openSettings() }
        } else if CommandLine.arguments.contains("--timeline") {
            TimelineController.shared.show()
        } else if CommandLine.arguments.contains("--welcome") {
            WelcomeController.shared.show()
        } else {
            Task {
                await WelcomeController.shared.showIfFirstRun()
                if !recorder.hasPermission, UserDefaults.standard.bool(forKey: Prefs.welcomeShown) { recorder.requestPermission() }
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
            Image(systemName: recorder.isRecording ? "record.circle" : "pause.circle")
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
        if let version = updater.availableVersion {
            Button("Update Available: \(version)…") { updater.checkForUpdates() }
        } else {
            Button("Check for Updates…") { updater.checkForUpdates() }
        }
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
            .simultaneousGesture(TapGesture().onEnded {
                DockPresence.windowWillOpen()
                DockPresence.frontOpenWindowsSoon()
            })
        Button("Quit TimeScreen") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var status: String {
        guard recorder.isRecording else {
            guard let until = recorder.pausedUntil else { return "Paused" }
            return "Paused until \(until.formatted(date: .omitted, time: .shortened))"
        }
        if let reason = recorder.skipReason { return reason }
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
