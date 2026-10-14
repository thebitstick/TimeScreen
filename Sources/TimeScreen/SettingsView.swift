import SwiftUI

struct SettingsView: View {
    @ObservedObject var recorder: Recorder

    var body: some View {
        TabView {
            GeneralPane().tabItem { Label("General", systemImage: "gearshape") }
            ScreenPane().tabItem { Label("Screen", systemImage: "display") }
            SummariesPane().tabItem { Label("Summaries", systemImage: "sparkles") }
            PrivacyPane().tabItem { Label("Privacy", systemImage: "lock") }
            StoragePane(recorder: recorder).tabItem { Label("Storage", systemImage: "externaldrive") }
            ShortcutsPane().tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .scenePadding()
        .frame(width: 520)
        .background(SettingsWindowPlacer())
    }
}

private struct SettingsWindowPlacer: NSViewRepresentable {
    final class Coordinator {
        var placed = false
        var observers: [NSObjectProtocol] = []
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            func place() {
                guard !coordinator.placed, let screen = window.screen ?? NSScreen.main else { return }
                let area = screen.visibleFrame
                let size = window.frame.size
                window.setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: area.minY + area.height * 0.62 - size.height / 2))
                coordinator.placed = true
            }
            place()
            DockPresence.bringToFront(window)
            coordinator.observers = [
                NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                    coordinator.placed = false
                },
                NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
                    MainActor.assumeIsolated {
                        place()
                        DockPresence.bringToFront(window)
                    }
                },
            ]
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

private struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralPane: View {
    @State private var checksForUpdates = Updater.shared.automaticallyChecks

    var body: some View {
        Form {
            LabeledContent("Startup:") { LaunchAtLoginToggle() }
            .padding(.vertical, 5)
            LabeledContent("Updates:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Check for updates automatically", isOn: $checksForUpdates)
                        .onChange(of: checksForUpdates) { _, on in Updater.shared.automaticallyChecks = on }
                    if Updater.isDevelopmentBuild {
                        Note("Development build: new versions are offered but never installed automatically.")
                    }
                    HStack {
                        Button("Check Now") { Updater.shared.checkForUpdates() }
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 5)
            LabeledContent("Timeline:") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Button("Open Timeline") { TimelineController.shared.show() }
                        Button("Show Welcome") { WelcomeController.shared.show() }
                    }
                    Note("Open it from the menu bar icon or with your shortcut. Esc closes it.")
                }
            }
            .padding(.vertical, 5)
        }
        .formStyle(.columns)
        .padding(.vertical, 8)
    }
}

private struct ScreenPane: View {
    @AppStorage(Prefs.interval) private var interval = 5.0
    @AppStorage(Prefs.ocr) private var ocr = true
    @AppStorage(Prefs.allDisplays) private var allDisplays = true
    @AppStorage(Prefs.pauseOnBattery) private var pauseOnBattery = false
    @AppStorage(Prefs.backoffWhenAway) private var backoffWhenAway = true
    @AppStorage(Prefs.pauseInLowPower) private var pauseInLowPower = false

    var body: some View {
        Form {
            Picker("Capture:", selection: $interval) {
                ForEach([2.0, 5, 10, 30, 60], id: \.self) { Text("Every \(Int($0)) seconds").tag($0) }
            }
            .fixedSize()
            .padding(.vertical, 5)
            LabeledContent("When away:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Capture less often when I'm away", isOn: $backoffWhenAway)
                    Note("After a minute without keyboard or mouse input captures slow to every 15 seconds, and to every 30 after five minutes. They return to normal the moment you're back.")
                }
            }
            .padding(.vertical, 5)
            LabeledContent("Displays:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Capture every display", isOn: $allDisplays)
                    Note("Turn off to capture only the main display. The timeline has a picker when you have more than one.")
                }
            }
            .padding(.vertical, 5)
            LabeledContent("Power:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Pause on battery power", isOn: $pauseOnBattery)
                    Toggle("Pause in Low Power Mode", isOn: $pauseInLowPower)
                    Note("Capturing and reading text uses energy. Recording resumes by itself when the condition ends. TimeScreen also pauses when less than 1 GB of disk space is free.")
                }
            }
            .padding(.vertical, 5)
            LabeledContent("Search:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Make screen text searchable", isOn: $ocr)
                    Note("Reads the text in each screenshot on this Mac, so you can find it later.")
                }
            }
            .padding(.vertical, 5)
        }
        .formStyle(.columns)
        .padding(.vertical, 8)
    }
}

private struct SummariesPane: View {
    @ObservedObject private var summarizer = Summarizer.shared
    @AppStorage(Prefs.autoSummaries) private var automatic = false
    @State private var stored = 0
    @State private var confirmDelete = false

    var body: some View {
        Form {
            LabeledContent("Model:") {
                VStack(alignment: .leading, spacing: 4) {
                    if let message = summarizer.availability.message {
                        Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Label("Apple's on-device model is ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    Button("Check Again") { summarizer.refreshAvailability() }
                    Note("Summaries are written on this Mac by Apple's on-device model, from the text TimeScreen read on your screen. Nothing is sent anywhere.")
                }
            }
            .padding(.vertical, 5)
            LabeledContent("Automatic:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Write summaries of finished 15-minute stretches", isOn: $automatic)
                    Note("Only while the Mac is idle and plugged in, and not in Low Power Mode. Hours and days are put together from those when you ask for them. Off by default, since it uses energy.")
                }
            }
            .padding(.vertical, 5)
            LabeledContent("Limits:") {
                Note("The model reads about 8,000 tokens at a time, roughly 20,000 characters, so long stretches are boiled down to their new lines first. Each summary takes a few seconds, and a whole day can take a few minutes. Summaries can be wrong or thin when a screen has little text, so check the screenshot.")
            }
            .padding(.vertical, 5)
            LabeledContent("Stored:") {
                HStack {
                    Text("\(stored) \(stored == 1 ? "summary" : "summaries")")
                    Button("Delete All…", role: .destructive) { confirmDelete = true }.disabled(stored == 0)
                }
            }
        }
        .formStyle(.columns)
        .padding(.vertical, 8)
        .task(id: summarizer.revision) { stored = (try? await Recorder.shared.db.summaryCount()) ?? 0 }
        .confirmationDialog("Delete every summary?", isPresented: $confirmDelete) {
            Button("Delete All", role: .destructive) { Task { await summarizer.deleteAll() } }
        } message: {
            Text("Screenshots are not touched. Summaries can be written again.")
        }
    }
}

private struct PrivacyPane: View {
    @AppStorage(Prefs.requireAuth) private var requireAuth = false
    @AppStorage(Prefs.authGrace) private var authGrace = 60.0
    @AppStorage(Prefs.excludedApps) private var excluded = Prefs.defaultExcluded
    @AppStorage(Prefs.skipPrivate) private var skipPrivate = true
    @AppStorage(Prefs.privateTitles) private var privateTitles = Prefs.defaultPrivateTitles
    @State private var lockMessage: String?

    private var lockToggle: Binding<Bool> {
        Binding(
            get: { requireAuth },
            set: { on in
                guard on else { requireAuth = false; lockMessage = nil; return }
                Task {
                    if await Authenticator.evaluate("Turn on the timeline lock") {
                        requireAuth = true
                        lockMessage = nil
                    } else {
                        lockMessage = "The lock wasn't turned on. Authenticate with Touch ID or your password to enable it."
                    }
                }
            })
    }

    var body: some View {
        Form {
            LabeledContent("Timeline lock:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Require Touch ID or your password to open the timeline", isOn: lockToggle)
                    if requireAuth {
                        Picker("Ask again:", selection: $authGrace) {
                            Text("Every time").tag(0.0)
                            Text("After 1 minute away").tag(60.0)
                            Text("After 5 minutes away").tag(300.0)
                            Text("After 15 minutes away").tag(900.0)
                        }
                        .fixedSize()
                    }
                    if let lockMessage { Text(lockMessage).font(.caption).foregroundStyle(.red) }
                    Note("Locks the timeline only, and it locks again when the Mac sleeps or the screen locks. Screenshots are ordinary files in the data folder, so turn on FileVault to protect them at rest.")
                }
            }
            .padding(.vertical, 5)
            LabeledContent("Private windows:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Don't capture a screen showing a private window", isOn: $skipPrivate)
                    if skipPrivate {
                        TextEditor(text: $privateTitles)
                            .font(.body.monospaced())
                            .frame(height: 70)
                            .border(Color.primary.opacity(0.15))
                    }
                    Note("A window is treated as private when its title contains one of these words, one per line. Browsers word this differently, so add your own.")
                    Note("Safari doesn't mark private windows in their titles, so they can't be detected. Add com.apple.Safari to Never capture below, or use Pause For in the menu bar.")
                }
            }
            .padding(.vertical, 5)
            LabeledContent("Never capture:") {
                VStack(alignment: .leading, spacing: 4) {
                    TextEditor(text: $excluded)
                        .font(.body.monospaced())
                        .frame(height: 90)
                        .border(Color.primary.opacity(0.15))
                    Note("Bundle identifiers, one per line. Nothing is recorded while one of these apps is frontmost.")
                }
            }
            .padding(.vertical, 5)
        }
        .formStyle(.columns)
        .padding(.vertical, 8)
    }
}

private struct StoragePane: View {
    @ObservedObject var recorder: Recorder
    @AppStorage(Prefs.retentionDays) private var retention = 30
    @AppStorage(Prefs.maxStorageGB) private var maxStorageGB = 0
    @AppStorage(Prefs.compactOld) private var compactOld = true
    @State private var usage: Int64 = 0
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Picker("Keep history:", selection: $retention) {
                ForEach([7, 14, 30, 90, 365], id: \.self) { Text("\($0) days").tag($0) }
                Text("Forever").tag(0)
            }
            .fixedSize()
            Note("Starred screenshots are never deleted by this or by the size limit.")
            .padding(.vertical, 5)
            LabeledContent("Size limit:") {
                VStack(alignment: .leading, spacing: 4) {
                    Picker("", selection: $maxStorageGB) {
                        Text("No limit").tag(0)
                        ForEach([5, 10, 20, 50, 100], id: \.self) { Text("\($0) GB").tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    Note("When history grows past this, the oldest screenshots are deleted first. Checked every few minutes.")
                }
            }
            .padding(.vertical, 5)
            LabeledContent("Space:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Shrink screenshots after a day", isOn: $compactOld)
                    Note("Older screenshots are shrunk to a smaller size once they're a day old.")
                }
            }
            .padding(.vertical, 5)
            LabeledContent("Used:") {
                HStack {
                    Text(ByteCountFormatter.string(fromByteCount: usage, countStyle: .file))
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([recorder.framesRoot]) }
                }
            }
            .padding(.vertical, 5)
            LabeledContent("Delete:") {
                Button("Delete All Captures…", role: .destructive) { confirmDelete = true }
            }
            .padding(.vertical, 5)
        }
        .formStyle(.columns)
        .padding(.vertical, 8)
        .task(id: recorder.revision) { usage = await recorder.diskUsage() }
        .confirmationDialog("Delete every capture?", isPresented: $confirmDelete) {
            Button("Delete All", role: .destructive) { Task { await recorder.deleteAll() } }
        } message: {
            Text("Screenshots and the search index are removed. This can't be undone.")
        }
    }
}

private struct ShortcutsPane: View {
    @AppStorage(Prefs.scrollToOpen) private var scrollToOpen = true

    var body: some View {
        Form {
            LabeledContent("Open Timeline:") {
                VStack(alignment: .leading, spacing: 4) {
                    ShortcutRecorder(hotkey: .timeline)
                    Note("Works from any app. Click the field, then press the keys you want.")
                }
            }
            .padding(.vertical, 5)
            LabeledContent("Pause / Resume:") {
                VStack(alignment: .leading, spacing: 4) {
                    ShortcutRecorder(hotkey: .pause)
                    Note("Pauses or resumes recording from any app, with a short sound so you know which. Not set by default.")
                }
            }
            .padding(.vertical, 5)
            LabeledContent("Star Moment:") {
                VStack(alignment: .leading, spacing: 4) {
                    ShortcutRecorder(hotkey: .star)
                    Note("Stars the newest screenshot from any app so it is kept forever. Plays a chime. Not set by default.")
                }
            }
            .padding(.vertical, 5)
            LabeledContent("Scroll to open:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Use Command + Shift + scroll to open the timeline", isOn: $scrollToOpen)
                    Note("Hold both keys and scroll with two fingers. Keep scrolling to scrub through time.")
                }
            }
            .padding(.vertical, 5)
        }
        .formStyle(.columns)
        .padding(.vertical, 8)
    }
}
