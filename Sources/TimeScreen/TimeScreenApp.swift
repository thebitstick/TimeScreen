import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        let recorder = Recorder.shared
        recorder.start()
        HotKey.shared.onPress = { TimelineController.shared.toggle() }
        HotKey.shared.registerFromPrefs()
        if !recorder.hasPermission { recorder.requestPermission() }
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
        }

        Settings {
            SettingsView(recorder: recorder)
        }
    }
}

struct MenuContent: View {
    @ObservedObject var recorder: Recorder

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
        Divider()
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
            .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
        Button("Quit TimeScreen") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var status: String {
        guard recorder.isRecording else { return "Paused" }
        let count = "\(recorder.framesToday) frames today"
        guard let last = recorder.lastCapture else { return count }
        return "\(count) · last \(last.formatted(date: .omitted, time: .standard))"
    }
}
