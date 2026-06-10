import Foundation
import UIKit

@MainActor
final class ComposerViewModel: ObservableObject {
    @Published var commandText = ""
    @Published var contextText = ""
    @Published var draftText = ""
    @Published var tone: ReplyTone = .natural
    @Published var isRecording = false
    @Published var isGenerating = false
    @Published var modelStatus = ModelStatus.checking
    @Published var statusLine: String?
    @Published var lastEngine: DraftEngine?
    @Published var gemmaStatus = "Gemma 4: pronto para importar .litertlm"

    private let speech = SpeechCommandRecognizer()
    private let generator = DraftGenerator()

    func refreshModelStatus() async {
        modelStatus = await generator.modelStatus()
    }

    func toggleRecording() async {
        if isRecording {
            await speech.stop()
            isRecording = false
            statusLine = "Pedido capturado. Ajuste se quiser e gere a mensagem."
            return
        }

        do {
            isRecording = true
            statusLine = "Ouvindo em português do Brasil..."
            try await speech.start { [weak self] transcript in
                Task { @MainActor in
                    self?.commandText = transcript
                }
            }
        } catch {
            isRecording = false
            statusLine = "Não consegui iniciar o microfone: \(error.localizedDescription)"
        }
    }

    func generateDraft() async {
        let trimmedCommand = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else {
            statusLine = "Me diga o que você quer escrever primeiro."
            return
        }

        isGenerating = true
        statusLine = "Gerando no aparelho..."
        defer { isGenerating = false }

        let request = DraftRequest(command: trimmedCommand, context: contextText, tone: tone)
        let result = await generator.generate(request)
        draftText = result.text
        lastEngine = result.engine
        UIPasteboard.general.string = result.text
        statusLine = "\(result.engine.title). \(result.diagnostic)"
    }

    func useExample(_ example: ComposerExample) {
        commandText = example.command
        contextText = example.context
        draftText = ""
        statusLine = nil
    }

    func copyDraft() {
        guard !draftText.isEmpty else { return }
        UIPasteboard.general.string = draftText
        statusLine = "Copiado."
    }

    func shareDraft() {
        guard !draftText.isEmpty else { return }
        let activity = UIActivityViewController(activityItems: [draftText], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController?
            .present(activity, animated: true)
    }

    func clear() {
        commandText = ""
        contextText = ""
        draftText = ""
        statusLine = nil
        lastEngine = nil
    }
}

struct ComposerExample: Identifiable {
    let id = UUID()
    let title: String
    let command: String
    let context: String

    static let samples = [
        ComposerExample(
            title: "Boa noite",
            command: "Responda pra ele que eu também amo ele, que ele tenha uma boa noite e que amanhã a gente volta a se falar.",
            context: "Boa noite, meu amor. Te amo, amanhã a gente se fala."
        ),
        ComposerExample(
            title: "Receita",
            command: "Escreva uma receita de bolo de fubá com ingredientes e passo a passo.",
            context: "Ele perguntou como faz bolo de fubá."
        ),
        ComposerExample(
            title: "Saudade",
            command: "Escreve uma mensagem carinhosa dizendo que estou com saudade e queria ver ele hoje.",
            context: ""
        )
    ]
}
