enum MenuBarState {
    static func symbol(hasPermission: Bool, isRecording: Bool, skip: SkipReason?, hasError: Bool) -> String {
        if !hasPermission { return "exclamationmark.triangle" }
        if !isRecording { return "pause.circle" }
        if let skip { return skip.symbol }
        if hasError { return "exclamationmark.circle" }
        return "record.circle"
    }

    static func description(hasPermission: Bool, isRecording: Bool, skip: SkipReason?, hasError: Bool) -> String {
        if !hasPermission { return "TimeScreen needs Screen Recording access" }
        if !isRecording { return "TimeScreen is paused" }
        if let skip { return skip.message }
        if hasError { return "TimeScreen hit an error while capturing" }
        return "TimeScreen is recording"
    }
}
