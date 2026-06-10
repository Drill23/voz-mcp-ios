import Foundation

struct KeyboardCommandExtraction: Equatable {
    enum Source: Equatable {
        case trigger
        case implicitCommand
    }

    let text: String
    let charactersToDelete: Int
    let source: Source
}

enum KeyboardCommandParser {
    static func extract(from context: String) -> KeyboardCommandExtraction? {
        if let triggered = extractTriggeredCommand(from: context) {
            return triggered
        }

        return extractImplicitCommand(from: context)
    }

    private static func extractTriggeredCommand(from context: String) -> KeyboardCommandExtraction? {
        let triggers = ["voz mcp", "vos mcp", "vós mcp", "mcp"]

        for trigger in triggers {
            if let range = context.range(of: trigger, options: [.caseInsensitive, .diacriticInsensitive, .backwards]) {
                guard hasWordBoundary(around: range, in: context) else { continue }
                let rawCommand = String(context[range.lowerBound...])
                let command = cleanCommandPrefix(String(context[range.upperBound...]))
                guard !command.isEmpty else { return nil }
                return KeyboardCommandExtraction(
                    text: command,
                    charactersToDelete: rawCommand.count,
                    source: .trigger
                )
            }
        }

        return nil
    }

    private static func extractImplicitCommand(from context: String) -> KeyboardCommandExtraction? {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (6...700).contains(trimmed.count) else { return nil }

        let folded = fold(trimmed)
        let startsLikeCommand = [
            "escrev",
            "respond",
            "respon",
            "manda",
            "mande",
            "diga",
            "fale",
            "fala",
            "crie",
            "faz",
            "faca",
            "faça",
            "reescrev",
            "melhore",
            "receita"
        ].contains { folded.hasPrefix($0) }

        let conversationalCommand = [
            "me ajuda a responder",
            "me ajude a responder",
            "quero responder",
            "preciso responder",
            "como respondo"
        ].contains { folded.hasPrefix($0) }

        let howToCommand = folded.hasPrefix("como ") && (folded.contains("passo a passo") || folded.contains("receita"))

        guard startsLikeCommand || conversationalCommand || howToCommand else { return nil }

        return KeyboardCommandExtraction(
            text: trimmed,
            charactersToDelete: context.count,
            source: .implicitCommand
        )
    }

    private static func cleanCommandPrefix(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":,.-–—")))
    }

    private static func hasWordBoundary(around range: Range<String.Index>, in text: String) -> Bool {
        let beforeIsBoundary: Bool
        if range.lowerBound == text.startIndex {
            beforeIsBoundary = true
        } else {
            let previous = text[text.index(before: range.lowerBound)]
            beforeIsBoundary = !previous.isLetter && !previous.isNumber
        }

        let afterIsBoundary: Bool
        if range.upperBound == text.endIndex {
            afterIsBoundary = true
        } else {
            let next = text[range.upperBound]
            afterIsBoundary = !next.isLetter && !next.isNumber
        }

        return beforeIsBoundary && afterIsBoundary
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR")).lowercased()
    }
}
