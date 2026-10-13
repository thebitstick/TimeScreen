import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var recorder: Recorder

    var body: some View {
        TabView {
            GeneralPane().tabItem { Label("General", systemImage: "gearshape") }
            ScreenPane().tabItem { Label("Screen", systemImage: "display") }
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
            NSApp.activate(ignoringOtherApps: true)
            window.orderFrontRegardless()
            coordinator.observers = [
                NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                    coordinator.placed = false
                },
                NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
                    place()
                    NSApp.activate(ignoringOtherApps: true)
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
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    var body: some View {
        Form {
            LabeledContent("Startup:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Open TimeScreen at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            do {
                                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                                launchError = nil
                            } catch {
                                launchError = error.localizedDescription
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            }
                        }
                    if let launchError { Text(launchError).font(.caption).foregroundStyle(.red) }
                }
            }
            .padding(.vertical, 5)
            LabeledContent("Timeline:") {
                VStack(alignment: .leading, spacing: 4) {
                    Button("Open Timeline") { TimelineController.shared.show() }
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
    @AppStorage(Prefs.excludedApps) private var excluded = Prefs.defaultExcluded
    @AppStorage(Prefs.skipPrivate) private var skipPrivate = true
    @AppStorage(Prefs.privateTitles) private var privateTitles = Prefs.defaultPrivateTitles

    var body: some View {
        Form {
            Picker("Capture:", selection: $interval) {
                ForEach([2.0, 5, 10, 30, 60], id: \.self) { Text("Every \(Int($0)) seconds").tag($0) }
            }
            .fixedSize()
            .padding(.vertical, 5)
            LabeledContent("Displays:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Capture every display", isOn: $allDisplays)
                    Note("Turn off to capture only the main display. The timeline has a picker when you have more than one.")
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
                    ShortcutRecorder()
                    Note("Works from any app. Click the field, then press the keys you want.")
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
