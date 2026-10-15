enum MenuBarState {
    static func symbol(hasPermission: Bool, isRecording: Bool, skip: SkipReason?, hasError: Bool) -> String {
        if !hasPermission { return "exclamationmark.triangle" }
        if !isRecording { return "pause.circle" }
        if let skip { return skip.symbol }
        if hasError { return "exclamationmark.circle" }
        return "record.circle"
    }

    static func description(hasPermission: Bool, isRecording: Bool, skip: SkipReason?, hasError: Bool) -> String {
        if !hasPermission { return String(localized: "TimeScreen needs Screen Recording access") }
        if !isRecording { return String(localized: "TimeScreen is paused") }
        if let skip { return skip.message }
        if hasError { return String(localized: "TimeScreen couldn't capture the screen. Open the menu for details.") }
        return String(localized: "TimeScreen is recording")
    }
}
