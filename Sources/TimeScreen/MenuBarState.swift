enum MenuBarState {
    static func symbol(hasPermission: Bool, isRecording: Bool, isSkipping: Bool, hasError: Bool) -> String {
        if !hasPermission { return "exclamationmark.triangle" }
        if !isRecording { return "pause.circle" }
        if isSkipping { return "eye.slash.circle" }
        if hasError { return "exclamationmark.circle" }
        return "record.circle"
    }

    static func description(hasPermission: Bool, isRecording: Bool, isSkipping: Bool, hasError: Bool) -> String {
        if !hasPermission { return "TimeScreen needs Screen Recording access" }
        if !isRecording { return "TimeScreen is paused" }
        if isSkipping { return "TimeScreen is not recording because a private window is open" }
        if hasError { return "TimeScreen hit an error while capturing" }
        return "TimeScreen is recording"
    }
}
