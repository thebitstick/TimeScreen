import AppKit
import SwiftUI

@MainActor
final class WelcomeController: NSObject, NSWindowDelegate {
    static let shared = WelcomeController()

    private var window: NSWindow?

    func showIfFirstRun() async {
        guard !UserDefaults.standard.bool(forKey: Prefs.welcomeShown) else { return }
        let hasHistory = !((try? await Recorder.shared.db.days()) ?? []).isEmpty
        if hasHistory { UserDefaults.standard.set(true, forKey: Prefs.welcomeShown) } else { show() }
    }

    func show() {
        if let window {
            DockPresence.bringToFront(window)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 100),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = String(localized: "Welcome to TimeScreen")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: WelcomeView(recorder: .shared) { [weak self] in self?.window?.close() })
        window.center()
        self.window = window
        DockPresence.bringToFront(window)
    }

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: Prefs.welcomeShown)
        window = nil
    }
}

private struct WelcomeView: View {
    @ObservedObject var recorder: Recorder
    @AppStorage(Prefs.hotkeyMods) private var mods = 2304
    @AppStorage(Prefs.hotkeyLabel) private var label = "T"
    let onDone: () -> Void

    private var shortcut: String { label.isEmpty ? String(localized: "your shortcut (none set)") : HotKey.describe(modifiers: UInt32(mods), label: label) }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                Text("Welcome to TimeScreen").font(.title.bold())
                Text("A searchable history of your screen. It all stays on this Mac, and nothing is sent anywhere.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 16) {
                step(1, "Allow Screen Recording",
                     recorder.hasPermission
                        ? "macOS needs your permission before TimeScreen can capture the screen."
                        : "macOS needs your permission before TimeScreen can capture the screen. After turning it on in System Settings, quit and reopen TimeScreen if it doesn't switch to Allowed.") {
                    if recorder.hasPermission {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Allow Access…") { recorder.requestPermission() }
                    }
                }
                step(2, "Look back in time",
                     "Press \(shortcut), or hold ⌘⇧ and scroll, to open the timeline. You can also use the menu bar icon. Esc closes it.") {
                    Button("Open Timeline") { TimelineController.shared.show() }
                }
                step(3, "Keep private things private",
                     "Password managers are never captured, and screens showing a private browsing window are skipped (not Safari's, see Settings). Pause anytime from the menu bar.") {
                    Button("Settings…") { DockPresence.openSettings() }
                }
            }

            Divider()
            HStack {
                LaunchAtLoginToggle()
                Spacer()
                Button("Done", action: onDone).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 540)
    }

    private func step<Trailing: View>(_ number: Int, _ title: LocalizedStringKey, _ detail: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)").font(.headline).foregroundStyle(.white)
                .frame(width: 28, height: 28).background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}
