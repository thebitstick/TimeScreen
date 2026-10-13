import ServiceManagement
import SwiftUI

struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Open TimeScreen at login", isOn: $enabled)
                .onChange(of: enabled) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        error = nil
                    } catch {
                        self.error = error.localizedDescription
                        enabled = SMAppService.mainApp.status == .enabled
                    }
                }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }
}
