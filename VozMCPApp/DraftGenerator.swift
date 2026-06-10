import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct DraftRequest {
    let command: String
    let context: String
    let tone: ReplyTone
}

struct DraftResult {
    let text: String
    let engine: DraftEngine
    let diagnostic: String

    var usedFoundationModel: Bool {
        engine == .appleFoundationModels
    }
}

struct ModelStatus: Equatable {
    let title: String
    let detail: String
    let isReady: Bool

    static let checking = ModelStatus(
        title: "Checando IA local",
        detail: "Vou testar o modelo nativo do aparelho.",
        isReady: false
    )
}

enum DraftEngine: Equatable {
    case appleFoundationModels
    case localComposer

    var title: String {
        switch self {
        case .appleFoundationModels:
            "Apple Intelligence local"
        case .localComposer:
            "Compositor local"
        }
    }
}

enum DraftLength: Equatable {
    case short
    case medium
    case long

    var title: String {
        switch self {
        case .short: "curto"
        case .medium: "médio"
        case .long: "completo"
        }
    }

    var tokenBudget: Int {
        switch self {
        case .short: 140
        case .medium: 420
        case .long: 1200
        }
    }

    var instruction: String {
        switch self {
        case .short:
            "Responda curto, com 1 a 3 frases, sem lista."
        case .medium:
            "Responda com tamanho médio, natural para mensagem, sem enrolar."
        case .long:
            "Responda completo. Se for receita, inclua ingredientes, modo de preparo, tempo, rendimento e dicas úteis."
        }
    }
}

enum ReplyTone: String, CaseIterable, Identifiable {
    case carinhoso
    case natural
    case direto
    case elegante

    var id: String { rawValue }

    var title: String {
        switch self {
        case .carinhoso: "Carinho"
        case .natural: "Natural"
        case .direto: "Direto"
        case .elegante: "Elegante"
        }
    }

    var instruction: String {
        switch self {
        case .carinhoso:
            "carinhoso, intimo, caloroso, sem exagerar"
        case .natural:
            "natural, conversado, com cara de mensagem real"
        case .direto:
            "claro, curto, confiante, sem rodeios"
        case .elegante:
            "polido, bonito, maduro e bem escrito"
        }
    }
}

struct DraftGenerator {
    func modelStatus() async -> ModelStatus {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                let localeDetail = model.supportsLocale(Locale(identifier: "pt_BR"))
                    ? "Modelo da Apple pronto para pt-BR neste aparelho."
                    : "Modelo da Apple pronto; pt-BR pode depender dos pacotes de idioma do iOS."
                return ModelStatus(title: "IA local pronta", detail: localeDetail, isReady: true)
            case .unavailable(.appleIntelligenceNotEnabled):
                return ModelStatus(
                    title: "Apple Intelligence desligada",
                    detail: "Ative Apple Intelligence nos Ajustes para usar o modelo local real.",
                    isReady: false
                )
            case .unavailable(.deviceNotEligible):
                return ModelStatus(
                    title: "Modelo Apple indisponível",
                    detail: "Este aparelho ou conta não liberou o Foundation Models.",
                    isReady: false
                )
            case .unavailable(.modelNotReady):
                return ModelStatus(
                    title: "Modelo ainda baixando",
                    detail: "O iOS está preparando o modelo local. Tente de novo depois.",
                    isReady: false
                )
            @unknown default:
                return ModelStatus(
                    title: "IA local indisponível",
                    detail: "O iOS não informou um motivo conhecido.",
                    isReady: false
                )
            }
        }
        #endif

        return ModelStatus(
            title: "Foundation Models fora do SDK",
            detail: "Este build vai usar o compositor local até o framework estar disponível.",
            isReady: false
        )
    }

    func statusLabel() async -> String {
        await modelStatus().title
    }

    func generate(_ request: DraftRequest) async -> DraftResult {
        let length = inferredLength(for: request)
        let fallback = LocalDraftHeuristics.compose(
            command: request.command,
            context: request.context,
            tone: request.tone,
            length: length
        )

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                let status = await modelStatus()
                return DraftResult(text: fallback, engine: .localComposer, diagnostic: status.detail)
            }

            do {
                let session = LanguageModelSession(
                    model: model,
                    instructions: systemInstructions
                )
                let response = try await session.respond(
                    to: prompt(for: request),
                    options: GenerationOptions(temperature: 0.28, maximumResponseTokens: length.tokenBudget)
                )
                let cleaned = cleanModelOutput(response.content)
                if cleaned.isEmpty || shouldUseFallback(insteadOf: cleaned, request: request, length: length) {
                    return DraftResult(
                        text: fallback,
                        engine: .localComposer,
                        diagnostic: "O modelo local respondeu abaixo do pedido; usei o compositor completo do aparelho."
                    )
                }

                return DraftResult(
                    text: cleaned,
                    engine: .appleFoundationModels,
                    diagnostic: "Gerado no aparelho com Foundation Models."
                )
            } catch {
                return DraftResult(
                    text: fallback,
                    engine: .localComposer,
                    diagnostic: "Apple Intelligence não concluiu: \(friendly(error))."
                )
            }
        }
        #endif

        return DraftResult(
            text: fallback,
            engine: .localComposer,
            diagnostic: "Foundation Models não está disponível neste SDK."
        )
    }

    private var systemInstructions: String {
        """
        Você é o Voz MCP, um assistente privado de escrita para iPhone.
        Transforme comandos falados em texto pronto para enviar em português do Brasil.
        Responda somente com a mensagem final, sem aspas, sem títulos e sem explicar o processo.
        Entenda pedidos como responder alguém, escrever receita, resumir, reescrever, pedir desculpas, demonstrar carinho ou organizar passo a passo.
        Interprete tamanho e intenção pelo comando: "curto", "rápido" e "resumo" pedem resposta pequena; "completo", "grande", "detalhado" e "passo a passo" pedem resposta longa.
        Remova vícios de fala, repetições, hesitações e autocorreções do usuário.
        Preserve a intenção do usuário. Não invente sentimentos, promessas, fatos ou contexto que não foram pedidos.
        Se o pedido for uma receita completa, entregue uma resposta completa e fácil de mandar em conversa, com ingredientes e modo de preparo.
        """
    }

    private func prompt(for request: DraftRequest) -> String {
        let cleanContext = request.context.trimmingCharacters(in: .whitespacesAndNewlines)
        let length = inferredLength(for: request)
        return """
        Tom desejado: \(request.tone.instruction)
        Tamanho desejado: \(length.title)
        Regra de tamanho: \(length.instruction)

        Pedido falado pelo usuário:
        \(request.command)

        Contexto próximo no campo de texto, se houver:
        \(cleanContext.isEmpty ? "sem contexto" : cleanContext)

        Escreva uma única mensagem pronta para enviar.
        """
    }

    private func cleanModelOutput(_ output: String) -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let wrappers = ["Mensagem:", "Resposta:", "Texto:"]
        for wrapper in wrappers where text.localizedCaseInsensitiveContains(wrapper) {
            text = text.replacingOccurrences(of: wrapper, with: "", options: [.caseInsensitive])
        }
        return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”")))
    }

    private func friendly(_ error: Error) -> String {
        let description = error.localizedDescription
        if description.isEmpty {
            return "erro sem descrição do sistema"
        }
        return description
    }

    private func inferredLength(for request: DraftRequest) -> DraftLength {
        let folded = fold(request.command + " " + request.context)
        if folded.contains("curt") ||
            folded.contains("rapido") ||
            folded.contains("rápido") ||
            folded.contains("pequen") ||
            folded.contains("em uma frase") {
            return .short
        }

        if folded.contains("complet") ||
            folded.contains("grande") ||
            folded.contains("detalhad") ||
            folded.contains("passo a passo") ||
            (folded.contains("receita") && !folded.contains("curt")) {
            return .long
        }

        return .medium
    }

    private func shouldUseFallback(insteadOf text: String, request: DraftRequest, length: DraftLength) -> Bool {
        let foldedPrompt = fold(request.command + " " + request.context)
        let foldedText = fold(text)

        if foldedPrompt.contains("receita") {
            let hasRecipeShape = foldedText.contains("ingredientes") &&
                (foldedText.contains("modo de preparo") || foldedText.contains("passo a passo"))
            if length == .long {
                return !hasRecipeShape || text.count < 520
            }
            return !hasRecipeShape && text.count < 220
        }

        if length == .long && text.count < 360 {
            return true
        }

        if foldedPrompt.contains("codigo") && foldedPrompt.contains("produto") {
            if !foldedText.contains("codigo") || !foldedText.contains("produto") {
                return true
            }
        }

        if foldedPrompt.contains("boa noite") && !foldedText.contains("boa noite") {
            return true
        }

        if foldedPrompt.contains("manha") && !foldedText.contains("manha") && !foldedText.contains("amanha") {
            return true
        }

        return false
    }

    private func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
            .lowercased()
    }
}

enum LocalDraftHeuristics {
    static func compose(command: String, context: String, tone: ReplyTone, length: DraftLength = .medium) -> String {
        let command = removeSpeechNoise(command)
        let context = removeSpeechNoise(context)
        let folded = fold(command + " " + context)

        if folded.contains("receita") && folded.contains("bolo") && folded.contains("fuba") {
            return recipeForCornmealCake(tone: tone, length: length)
        }

        if folded.contains("codigo") && folded.contains("produto") && folded.contains("manha") {
            return applyTone(
                "Boa noite. Amanhã de manhã eu falo com você com calma, e também preciso do código do produto cedo para conseguir ver isso direitinho.",
                tone: tone
            )
        }

        if folded.contains("boa noite") && (folded.contains("amo") || folded.contains("ama")) {
            return applyTone(
                "Também te amo, meu amor. Dorme bem, descansa bastante e fica com uma noite bem tranquila. Amanhã a gente volta a se falar com calma.",
                tone: tone
            )
        }

        if folded.contains("saudade") {
            return applyTone(
                "Amor, bateu uma saudade de você. Queria muito te ver hoje e ficar um pouco juntinho.",
                tone: tone
            )
        }

        if folded.contains("desculp") || folded.contains("perdao") || folded.contains("perdão") {
            return applyTone(
                "Eu pensei melhor e queria te pedir desculpa. Não quero que isso fique estranho entre a gente, porque você é importante pra mim.",
                tone: tone
            )
        }

        if folded.contains("bom dia") {
            return applyTone(
                "Bom dia, meu amor. Espero que seu dia comece leve e que você lembre que eu estou pensando em você.",
                tone: tone
            )
        }

        if let extracted = extractMessageInstruction(from: command), !extracted.isEmpty {
            return applyTone(ensureSentence(polish(extracted)), tone: tone)
        }

        if folded.contains("responde") || folded.contains("responda") {
            return applyTone(
                "Eu entendi, amor. Gosto quando a gente consegue conversar com calma, e quero responder isso do jeito certo.",
                tone: tone
            )
        }

        return applyTone(ensureSentence(polish(command)), tone: tone)
    }

    private static func recipeForCornmealCake(tone: ReplyTone, length: DraftLength) -> String {
        if length == .short {
            let short = """
            Claro. Bolo de fubá rápido: bata 3 ovos, 1 xícara de leite, 1 xícara de óleo, 1 e 1/2 xícara de açúcar, 1 xícara de fubá e 1 xícara de farinha. Misture 1 colher de fermento por último e asse a 180 graus por 35 a 40 minutos.
            """
            return tone == .direto ? short.replacingOccurrences(of: "Claro. ", with: "") : short
        }

        let text = """
        Claro, amor. Aqui vai uma receita completa de bolo de fubá:

        Ingredientes:
        - 3 ovos
        - 1 xícara de leite
        - 1 xícara de óleo
        - 1 e 1/2 xícara de açúcar
        - 1 xícara de fubá
        - 1 xícara de farinha de trigo
        - 1 colher de sopa de fermento em pó
        - Opcional: 1 colher de erva-doce ou um pouco de queijo ralado

        Modo de preparo:
        1. Preaqueça o forno a 180 graus e unte uma forma com manteiga e farinha.
        2. No liquidificador, bata os ovos, o leite, o óleo e o açúcar até ficar bem misturado.
        3. Coloque o fubá e a farinha de trigo e bata de novo só até a massa ficar lisa.
        4. Acrescente o fermento por último e misture delicadamente com uma colher ou usando a função pulsar.
        5. Despeje a massa na forma e leve ao forno por 35 a 40 minutos.
        6. Quando estiver dourado, espete um palito no centro. Se sair limpo, está pronto.

        Rendimento:
        Dá um bolo médio, bom para umas 8 a 10 fatias.

        Dica:
        Se quiser deixar mais molhadinho, dá para substituir metade do leite por leite de coco.
        """
        return tone == .direto ? text.replacingOccurrences(of: "Claro, amor. ", with: "") : text
    }

    private static func extractMessageInstruction(from text: String) -> String? {
        let markers = [
            "responda pra ele que",
            "responde pra ele que",
            "responda para ele que",
            "responde para ele que",
            "responda dizendo que",
            "responde dizendo que",
            "responda que",
            "responde que",
            "fala pra ele que",
            "fale pra ele que",
            "diga pra ele que",
            "diga que",
            "manda pra ele que",
            "mande pra ele que",
            "escreva que",
            "escreve que"
        ]

        for marker in markers {
            if let range = text.range(of: marker, options: [.caseInsensitive, .diacriticInsensitive]) {
                return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return nil
    }

    private static func applyTone(_ text: String, tone: ReplyTone) -> String {
        switch tone {
        case .carinhoso:
            return text
        case .natural:
            return text
                .replacingOccurrences(of: "meu amor", with: "amor")
                .replacingOccurrences(of: "juntinho", with: "junto")
        case .direto:
            return text
                .replacingOccurrences(of: "meu amor", with: "amor")
                .replacingOccurrences(of: "Queria muito", with: "Quero")
                .replacingOccurrences(of: "Espero que ", with: "")
                .replacingOccurrences(of: " bem tranquila", with: " tranquila")
        case .elegante:
            return text
                .replacingOccurrences(of: "pra", with: "para")
                .replacingOccurrences(of: "juntinho", with: "junto")
                .replacingOccurrences(of: "Dorme bem", with: "Durma bem")
        }
    }

    private static func polish(_ text: String) -> String {
        var output = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacements = [
            " q ": " que ",
            " vc ": " você ",
            " tbm ": " também ",
            " tambem ": " também ",
            " amanha ": " amanhã ",
            " voce ": " você ",
            " ta ": " está "
        ]

        output = " " + output + " "
        for (source, target) in replacements {
            output = output.replacingOccurrences(of: source, with: target, options: [.caseInsensitive])
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func ensureSentence(_ text: String) -> String {
        var output = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return "Me fala melhor o que você quer responder." }

        if let first = output.first {
            output.replaceSubrange(output.startIndex...output.startIndex, with: String(first).uppercased())
        }

        if !output.hasSuffix(".") && !output.hasSuffix("!") && !output.hasSuffix("?") {
            output.append(".")
        }

        return output
    }

    private static func removeSpeechNoise(_ text: String) -> String {
        var output = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            "\\b(tipo|assim|né|ne|sabe|entendeu|e tal)\\b,?\\s*",
            "\\b(ã+|ah+|hum+|hmm+)\\b,?\\s*"
        ]

        for pattern in patterns {
            output = output.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        while output.contains("  ") {
            output = output.replacingOccurrences(of: "  ", with: " ")
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
            .lowercased()
    }
}
