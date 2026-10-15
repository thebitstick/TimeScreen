import Foundation

/// SQLite's search index treats an unbroken run of Chinese or Japanese characters as one word, so a word in the middle of a
/// sentence can't be found. Indexing each character on its own, with an invisible separator that is removed again when the text
/// is read back, makes any run searchable without changing what is shown or copied.
enum CJKText {
    private static let separator: Character = "\u{200B}"

    static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x31F0...0x31FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F: true
        default: false
        }
    }

    static func spaced(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: isCJK) else { return text }
        var result = ""
        result.reserveCapacity(text.count * 2)
        var previousWasCJK = false
        for character in text {
            let isCJK = character.unicodeScalars.contains(where: isCJK)
            if isCJK, previousWasCJK { result.append(separator) }
            result.append(character)
            previousWasCJK = isCJK
        }
        return result
    }

    static func unspaced(_ text: String) -> String {
        text.contains(separator) ? text.replacingOccurrences(of: String(separator), with: "") : text
    }
}
