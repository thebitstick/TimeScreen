import SwiftUI

struct SettingsView: View {
    @ObservedObject var recorder: Recorder
    @AppStorage("settingsTab") private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            GeneralPane().tabItem { Label("General", systemImage: "gearshape") }.tag(0)
            CapturePane().tabItem { Label("Capture", systemImage: "display") }.tag(1)
            SummariesPane().tabItem { Label("Summaries", systemImage: "sparkles") }.tag(2)
            PrivacyPane().tabItem { Label("Privacy", systemImage: "lock") }.tag(3)
            StoragePane(recorder: recorder).tabItem { Label("Storage", systemImage: "externaldrive") }.tag(4)
            ShortcutsPane().tabItem { Label("Shortcuts", systemImage: "keyboard") }.tag(5)
        }
        .scenePadding()
        .frame(width: 520)
        .background(SettingsWindowPlacer())
    }
}

private struct SettingsWindowPlacer: NSViewRepresentable {
    @MainActor
    final class Coordinator {
        var placed = false
        var observers: [NSObjectProtocol] = []

        func place(_ window: NSWindow) {
            guard !placed, let screen = window.screen ?? NSScreen.main else { return }
            let area = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: area.minY + area.height * 0.62 - size.height / 2))
            placed = true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        Task { @MainActor in
            guard let window = view.window else { return }
            coordinator.place(window)
            DockPresence.bringToFront(window)
            coordinator.observers = [
                NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                    MainActor.assumeIsolated { coordinator.placed = false }
                },
                NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
                    MainActor.assumeIsolated {
                        coordinator.place(window)
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
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

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
                    Toggle("Check for updates automatically", isOn: $checksForUpdates).fixedSize(horizontal: false, vertical: true)
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

private struct CapturePane: View {
    @AppStorage(Prefs.interval) private var interval = 5.0
    @AppStorage(Prefs.ocr) private var ocr = true
    @AppStorage(Prefs.allDisplays) private var allDisplays = true
    @AppStorage(Prefs.pauseOnBattery) private var pauseOnBattery = false
    @AppStorage(Prefs.backoffWhenAway) private var backoffWhenAway = true
    @AppStorage(Prefs.pauseInLowPower) private var pauseInLowPower = false

    var body: some View {
        Form {
            Picker("Frequency:", selection: $interval) {
                ForEach([2.0, 5, 10, 30, 60], id: \.self) { Text("Every \(Int($0)) seconds").tag($0) }
            }
            .fixedSize()
            .padding(.vertical, 5)
            LabeledContent("When away:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Capture less often when I'm away", isOn: $backoffWhenAway).fixedSize(horizontal: false, vertical: true)
                    Note("After a minute without keyboard or mouse input captures slow to every 15 seconds, and to every 30 after five minutes. They return to normal the moment you're back.")
                }
            }
            .padding(.vertical, 5)
            LabeledContent("Displays:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Capture every display", isOn: $allDisplays).fixedSize(horizontal: false, vertical: true)
                    Note("Turn off to capture only the main display. The timeline has a picker when you have more than one.")
                }
            }
            .padding(.vertical, 5)
            LabeledContent("Power:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Pause on battery power", isOn: $pauseOnBattery).fixedSize(horizontal: false, vertical: true)
                    Toggle("Pause in Low Power Mode", isOn: $pauseInLowPower).fixedSize(horizontal: false, vertical: true)
                    Note("Capturing and reading text uses energy. Recording resumes by itself when the condition ends. TimeScreen also pauses when less than 1 GB of disk space is free.")
                }
            }
            .padding(.vertical, 5)
            LabeledContent("Search:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Make screen text searchable", isOn: $ocr).fixedSize(horizontal: false, vertical: true)
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
                        Label("On-device Apple Intelligence is ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    Button("Check Again") { summarizer.refreshAvailability() }
                    Note("Summaries are written on this Mac by on-device Apple Intelligence, from the text TimeScreen read on your screen. Nothing is sent anywhere.")
                }
            }
            .padding(.vertical, 5)
            LabeledContent("Automatic:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Write summaries in the background", isOn: $automatic).fixedSize(horizontal: false, vertical: true)
                    Note("Finished 15-minute stretches and hours are written ahead of time, so a day's recap only has to put them together. It only runs while the Mac is idle and plugged in, and not in Low Power Mode, and stops as soon as you use the Mac. Turn it off to write summaries only when you ask.")
                }
            }
            .padding(.vertical, 5)
            LabeledContent("Limits:") {
                Note("Apple Intelligence can only read a limited amount of text at once, so long stretches are boiled down to their new lines first. Each summary takes a few seconds, and a whole day can take a few minutes. Summaries can be wrong or thin when a screen has little text, so check the screenshot.")
            }
            .padding(.vertical, 5)
            LabeledContent("Stored:") {
                HStack {
                    Text("\(stored) summaries")
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
                    if await Authenticator.evaluate(String(localized: "Turn on the timeline lock")) {
                        requireAuth = true
                        lockMessage = nil
                    } else {
                        lockMessage = String(localized: "The lock wasn't turned on. Authenticate with Touch ID or your password to enable it.")
                    }
                }
            })
    }

    var body: some View {
        Form {
            LabeledContent("Timeline lock:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Require Touch ID or your password to open the timeline", isOn: lockToggle).fixedSize(horizontal: false, vertical: true)
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
                    Toggle("Don't capture a screen showing a private window", isOn: $skipPrivate).fixedSize(horizontal: false, vertical: true)
                    if skipPrivate {
                        TextEditor(text: $privateTitles)
                            .font(.body.monospaced())
                            .frame(height: 100)
                            .border(Color.primary.opacity(0.15))
                    }
                    Note("A window is treated as private when its title contains one of these words, one per line. Browsers word this differently, so add your own.")
                    Note("Safari doesn't mark private windows in their titles, so they can't be detected. Add Safari to Never capture below, or use Pause For in the menu bar.")
                }
            }
            .padding(.vertical, 5)
            LabeledContent("Never capture:") {
                VStack(alignment: .leading, spacing: 4) {
                    ExcludedAppsList(raw: $excluded)
                    Note("Nothing is captured while one of these apps is the front app.")
                }
            }
            .padding(.vertical, 5)
        }
        .formStyle(.columns)
        .padding(.vertical, 8)
    }
}

private struct ExcludedAppsList: View {
    @Binding var raw: String
    @State private var selection: String?

    private var ids: [String] { ExcludedApps.parse(raw) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            List(ids, id: \.self, selection: $selection) { id in
                HStack(spacing: 8) {
                    Image(nsImage: icon(for: id)).resizable().frame(width: 18, height: 18)
                    if let name = name(for: id) {
                        Text(name)
                    } else {
                        Text(id).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text("Not installed").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 110)
            .border(Color.primary.opacity(0.15))
            HStack(spacing: 4) {
                Button { chooseApps() } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add an app")
                Button {
                    if let selection { raw = ExcludedApps.removing(selection, from: raw) }
                    selection = nil
                } label: { Image(systemName: "minus") }
                    .accessibilityLabel("Remove the selected app")
                    .disabled(selection == nil)
            }
        }
    }

    private func url(for id: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }

    private func name(for id: String) -> String? {
        url(for: id).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
    }

    private func icon(for id: String) -> NSImage {
        url(for: id).map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.message = String(localized: "Choose the apps TimeScreen should never capture.")
        panel.prompt = String(localized: "Add")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier { raw = ExcludedApps.adding(id, to: raw) }
        }
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
                    Toggle("Shrink screenshots after a day", isOn: $compactOld).fixedSize(horizontal: false, vertical: true)
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
                Button("Delete All Screenshots…", role: .destructive) { confirmDelete = true }
            }
            .padding(.vertical, 5)
        }
        .formStyle(.columns)
        .padding(.vertical, 8)
        .task(id: recorder.revision) { usage = await recorder.diskUsage() }
        .confirmationDialog("Delete every screenshot?", isPresented: $confirmDelete) {
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
                    Toggle("Use Command + Shift + scroll to open the timeline", isOn: $scrollToOpen).fixedSize(horizontal: false, vertical: true)
                    Note("Hold both keys and scroll with two fingers. Keep scrolling to scrub through time.")
                }
            }
            .padding(.vertical, 5)
        }
        .formStyle(.columns)
        .padding(.vertical, 8)
    }
}
