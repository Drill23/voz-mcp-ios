import Foundation

struct DraftValidationCase {
    let name: String
    let request: DraftRequest
    let requiredFragments: [String]
    let forbiddenFragments: [String]
    let minimumCharacters: Int
    let maximumCharacters: Int?
}

@main
struct ValidateDrafts {
    static func main() async {
        let cases = [
            DraftValidationCase(
                name: "codigo do produto e boa noite",
                request: DraftRequest(
                    command: "responda dizendo que eu vou falar com ele pela manhã, deu um boa noite, e diga que eu preciso do código do produto amanhã cedo",
                    context: "Boa noite meu amor, te amo. Amanhã a gente se fala.",
                    tone: .natural
                ),
                requiredFragments: ["boa noite", "amanhã", "código do produto", "você"],
                forbiddenFragments: ["diga que", "responda", "ele pela manhã"],
                minimumCharacters: 120,
                maximumCharacters: 360
            ),
            DraftValidationCase(
                name: "receita completa bolo de fuba",
                request: DraftRequest(
                    command: "escreva uma receita completa grande de bolo de fubá com ingredientes e modo de preparo",
                    context: "Ele perguntou como faz bolo de fubá.",
                    tone: .natural
                ),
                requiredFragments: ["ingredientes", "modo de preparo", "rendimento", "bolo de fubá"],
                forbiddenFragments: ["não sei", "me diga"],
                minimumCharacters: 520,
                maximumCharacters: nil
            ),
            DraftValidationCase(
                name: "receita curta bolo de fuba",
                request: DraftRequest(
                    command: "escreva uma receita curta de bolo de fubá",
                    context: "",
                    tone: .natural
                ),
                requiredFragments: ["bolo de fubá", "asse"],
                forbiddenFragments: ["modo de preparo:", "rendimento:"],
                minimumCharacters: 120,
                maximumCharacters: 330
            ),
            DraftValidationCase(
                name: "mensagem carinhosa saudade",
                request: DraftRequest(
                    command: "escreve uma mensagem carinhosa dizendo que estou com saudade e queria ver ele hoje",
                    context: "",
                    tone: .natural
                ),
                requiredFragments: ["estou com saudade", "você"],
                forbiddenFragments: ["mensagem carinhosa", "dizendo que", "você está com saudade", "que tal ver você"],
                minimumCharacters: 45,
                maximumCharacters: 220
            )
        ]

        var failures: [String] = []
        let generator = DraftGenerator()

        for validation in cases {
            let result = await generator.generate(validation.request)
            let folded = fold(result.text)

            for fragment in validation.requiredFragments where !folded.contains(fold(fragment)) {
                failures.append("\(validation.name): missing '\(fragment)' in: \(result.text)")
            }

            for fragment in validation.forbiddenFragments where folded.contains(fold(fragment)) {
                failures.append("\(validation.name): forbidden '\(fragment)' in: \(result.text)")
            }

            if result.text.count < validation.minimumCharacters {
                failures.append("\(validation.name): too short (\(result.text.count)): \(result.text)")
            }

            if let max = validation.maximumCharacters, result.text.count > max {
                failures.append("\(validation.name): too long (\(result.text.count)): \(result.text)")
            }

            print("PASS? \(validation.name)")
            print(result.text)
            print("---")
        }

        if failures.isEmpty {
            failures += validateKeyboardParser()
        }

        if failures.isEmpty {
            print("All draft and keyboard validations passed.")
        } else {
            fputs(failures.joined(separator: "\n") + "\n", stderr)
            exit(1)
        }
    }

    private static func validateKeyboardParser() -> [String] {
        var failures: [String] = []

        let triggeredContext = "Tudo bem. voz mcp responda dizendo que amanhã eu mando o código do produto"
        if let extraction = KeyboardCommandParser.extract(from: triggeredContext) {
            assertEqual("trigger command text", extraction.text, "responda dizendo que amanhã eu mando o código do produto", &failures)
            assertEqual("trigger source", extraction.source, .trigger, &failures)
            assertEqual("trigger delete count", extraction.charactersToDelete, "voz mcp responda dizendo que amanhã eu mando o código do produto".count, &failures)
        } else {
            failures.append("trigger command: parser returned nil")
        }

        let implicitContext = "escreva uma receita completa de bolo de fubá"
        if let extraction = KeyboardCommandParser.extract(from: implicitContext) {
            assertEqual("implicit command text", extraction.text, implicitContext, &failures)
            assertEqual("implicit source", extraction.source, .implicitCommand, &failures)
            assertEqual("implicit delete count", extraction.charactersToDelete, implicitContext.count, &failures)
        } else {
            failures.append("implicit command: parser returned nil")
        }

        let normalDraft = "Acho que amanhã a gente fala sobre o produto com calma"
        if KeyboardCommandParser.extract(from: normalDraft) != nil {
            failures.append("normal draft should not be treated as command")
        }

        let incompleteTrigger = "voz mcp "
        if KeyboardCommandParser.extract(from: incompleteTrigger) != nil {
            failures.append("incomplete trigger should not be treated as command")
        }

        if failures.isEmpty {
            print("Keyboard parser validations passed.")
        }
        return failures
    }

    private static func assertEqual<T: Equatable>(_ name: String, _ actual: T, _ expected: T, _ failures: inout [String]) {
        if actual != expected {
            failures.append("\(name): expected \(expected), got \(actual)")
        }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR")).lowercased()
    }
}
