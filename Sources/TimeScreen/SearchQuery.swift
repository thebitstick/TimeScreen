import Foundation

/// What the search box means: words match as prefixes, "quoted words" match exactly and in order, and a leading minus leaves
/// a word or phrase out.
struct SearchQuery: Equatable {
    enum Term: Equatable {
        case word(String)
        case phrase(String)

        var words: [String] {
            switch self {
            case .word(let word): [word]
            case .phrase(let phrase): phrase.split(separator: " ").map(String.init)
            }
        }
    }

    private(set) var included: [Term] = []
    private(set) var excluded: [Term] = []

    init(_ text: String) {
        var rest = Substring(text)
        while let first = rest.first {
            if first.isWhitespace { rest = rest.dropFirst(); continue }
            var negative = false
            if first == "-", rest.count > 1 {
                negative = true
                rest = rest.dropFirst()
            }
            let term: Term?
            if rest.first == "\"" {
                rest = rest.dropFirst()
                let end = rest.firstIndex(of: "\"") ?? rest.endIndex
                let phrase = rest[..<end].split(whereSeparator: \.isWhitespace).joined(separator: " ")
                rest = end < rest.endIndex ? rest[rest.index(after: end)...] : rest[end...]
                term = phrase.isEmpty ? nil : .phrase(phrase)
            } else {
                let end = rest.firstIndex(where: \.isWhitespace) ?? rest.endIndex
                let word = rest[..<end].replacingOccurrences(of: "\"", with: "")
                rest = rest[end...]
                term = word.isEmpty ? nil : .word(word)
            }
            guard let term else { continue }
            if negative { excluded.append(term) } else { included.append(term) }
        }
    }

    /// Nil when there is nothing to match: no words, or only words to leave out.
    var matchExpression: String? {
        guard !included.isEmpty else { return nil }
        func render(_ term: Term) -> String {
            switch term {
            case .word(let word): "\"\(CJKText.spaced(word))\"*"
            case .phrase(let phrase): "\"\(CJKText.spaced(phrase))\""
            }
        }
        let positive = included.map(render).joined(separator: " ")
        guard !excluded.isEmpty else { return positive }
        return "(\(positive)) NOT (\(excluded.map(render).joined(separator: " OR ")))"
    }

    /// Lowercased words to mark on a screenshot or in its text. Left-out words are not highlighted.
    var highlightTerms: [String] {
        included.flatMap(\.words).map { $0.lowercased() }
    }
}
