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
        case .short: 160
        case .medium: 520
        case .long: 1400
        }
    }

    var instruction: String {
        switch self {
        case .short:
            "Mensagem curta, uma a tres frases, sem lista."
        case .medium:
            "Mensagem natural de tamanho medio, com todos os pontos do pedido."
        case .long:
            "Mensagem completa. Se houver receita ou passo a passo, inclua secoes claras e detalhes suficientes."
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
            "carinhoso, humano, proximo, sem exagerar"
        case .natural:
            "natural, conversado, com cara de mensagem real"
        case .direto:
            "curto, claro, objetivo, sem floreio"
        case .elegante:
            "polido, cuidadoso, maduro e bem escrito"
        }
    }
}

enum DraftKind: Equatable {
    case reply
    case recipe
    case instruction
    case freeform
}

struct DraftIntent: Equatable {
    let rawCommand: String
    let cleanedCommand: String
    let kind: DraftKind
    let length: DraftLength
    let toneOverride: ReplyTone?
    let mustInclude: [String]
    let mustIncludeGroups: [[String]]
    let subject: String?

    var checklist: String {
        var items = mustInclude.map { "- incluir: \($0)" }
        items += mustIncludeGroups.map { "- incluir pelo menos um destes termos: \($0.joined(separator: ", "))" }
        if items.isEmpty {
            return "- preservar a intencao do usuario"
        }
        return items.joined(separator: "\n")
    }
}

struct DraftGenerator {
    func modelStatus() async -> ModelStatus {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                let detail = model.supportsLocale(Locale(identifier: "pt_BR"))
                    ? "Modelo da Apple pronto para pt-BR neste aparelho."
                    : "Modelo da Apple pronto; pt-BR pode depender dos pacotes de idioma do iOS."
                return ModelStatus(title: "IA local pronta", detail: detail, isReady: true)
            case .unavailable(.appleIntelligenceNotEnabled):
                return ModelStatus(
                    title: "Apple Intelligence desligada",
                    detail: "Ative Apple Intelligence nos Ajustes para usar o modelo local real.",
                    isReady: false
                )
            case .unavailable(.deviceNotEligible):
                return ModelStatus(
                    title: "Modelo Apple indisponível",
                    detail: "Este aparelho ou conta nao liberou o Foundation Models.",
                    isReady: false
                )
            case .unavailable(.modelNotReady):
                return ModelStatus(
                    title: "Modelo ainda baixando",
                    detail: "O iOS esta preparando o modelo local. Tente de novo depois.",
                    isReady: false
                )
            @unknown default:
                return ModelStatus(
                    title: "IA local indisponível",
                    detail: "O iOS nao informou um motivo conhecido.",
                    isReady: false
                )
            }
        }
        #endif

        return ModelStatus(
            title: "Foundation Models fora do SDK",
            detail: "Este build usa o compositor local ate o framework estar disponivel.",
            isReady: false
        )
    }

    func statusLabel() async -> String {
        await modelStatus().title
    }

    func generate(_ request: DraftRequest) async -> DraftResult {
        let intent = DraftIntentAnalyzer.analyze(request)
        let effectiveTone = intent.toneOverride ?? request.tone
        let fallback = SmartLocalComposer.compose(intent: intent, tone: effectiveTone)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                let status = await modelStatus()
                return DraftResult(text: fallback, engine: .localComposer, diagnostic: status.detail)
            }

            do {
                let session = LanguageModelSession(model: model, instructions: systemInstructions)
                let response = try await session.respond(
                    to: prompt(for: request, intent: intent, tone: effectiveTone),
                    options: GenerationOptions(temperature: 0.22, maximumResponseTokens: intent.length.tokenBudget)
                )
                let cleaned = cleanModelOutput(response.content)
                if cleaned.isEmpty || !DraftQualityGate.accepts(cleaned, intent: intent) {
                    return DraftResult(
                        text: fallback,
                        engine: .localComposer,
                        diagnostic: "O modelo local nao cumpriu todo o pedido; usei uma resposta estruturada no aparelho."
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
                    diagnostic: "Apple Intelligence nao concluiu: \(friendly(error))."
                )
            }
        }
        #endif

        return DraftResult(
            text: fallback,
            engine: .localComposer,
            diagnostic: "Foundation Models nao esta disponivel neste SDK."
        )
    }

    private var systemInstructions: String {
        """
        Voce e o Voz MCP, um assistente privado de escrita para iPhone.
        Transforme comandos falados em uma unica mensagem pronta para enviar em portugues do Brasil.
        Nunca explique o processo. Nunca ofereca alternativas. Nunca coloque aspas em volta da resposta.
        Preserve todos os requisitos do usuario, inclusive horario, tom, pedido de codigo, produto, desculpas, boa noite, amor, receita, ingredientes e modo de preparo.
        Remova vicios de fala e organize a mensagem com cuidado.
        Se o usuario pedir texto completo, escreva completo. Se pedir curto, seja curto.
        """
    }

    private func prompt(for request: DraftRequest, intent: DraftIntent, tone: ReplyTone) -> String {
        let context = request.context.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        Tipo de texto: \(intent.kind)
        Tom: \(tone.instruction)
        Tamanho: \(intent.length.title)
        Regra de tamanho: \(intent.length.instruction)

        Checklist obrigatorio:
        \(intent.checklist)

        Pedido falado pelo usuario:
        \(request.command)

        Contexto no campo ativo:
        \(context.isEmpty ? "sem contexto" : context)

        Escreva somente a mensagem final.
        """
    }

    private func cleanModelOutput(_ output: String) -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        for wrapper in ["Mensagem:", "Resposta:", "Texto final:", "Texto:"] {
            text = text.replacingOccurrences(of: wrapper, with: "", options: [.caseInsensitive])
        }
        return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”")))
    }

    private func friendly(_ error: Error) -> String {
        let description = error.localizedDescription
        return description.isEmpty ? "erro sem descricao do sistema" : description
    }
}

enum DraftIntentAnalyzer {
    static func analyze(_ request: DraftRequest) -> DraftIntent {
        let cleaned = clean(request.command)
        let folded = fold(cleaned + " " + request.context)
        let kind = inferKind(from: folded)
        let length = inferLength(from: folded, kind: kind)
        let tone = inferTone(from: folded)
        let subject = inferSubject(from: folded)
        let mustInclude = inferRequiredTerms(from: folded, kind: kind, subject: subject)
        let groups = inferRequiredGroups(from: folded, kind: kind)

        return DraftIntent(
            rawCommand: request.command,
            cleanedCommand: cleaned,
            kind: kind,
            length: length,
            toneOverride: tone,
            mustInclude: mustInclude,
            mustIncludeGroups: groups,
            subject: subject
        )
    }

    private static func inferKind(from folded: String) -> DraftKind {
        if folded.contains("receita") {
            return .recipe
        }
        if folded.contains("passo a passo") || folded.contains("tutorial") || folded.contains("como fazer") {
            return .instruction
        }
        if folded.contains("respond") || folded.contains("responda") || folded.contains("diga") || folded.contains("fale") || folded.contains("mande") {
            return .reply
        }
        return .freeform
    }

    private static func inferLength(from folded: String, kind: DraftKind) -> DraftLength {
        if folded.contains("curt") || folded.contains("rapido") || folded.contains("pequen") || folded.contains("uma frase") {
            return .short
        }
        if folded.contains("complet") || folded.contains("grande") || folded.contains("detalhad") || folded.contains("passo a passo") {
            return .long
        }
        return kind == .recipe ? .long : .medium
    }

    private static func inferTone(from folded: String) -> ReplyTone? {
        if folded.contains("carinhos") || folded.contains("fof") || folded.contains("amoros") || folded.contains("com carinho") {
            return .carinhoso
        }
        if folded.contains("elegant") || folded.contains("polid") || folded.contains("profissional") || folded.contains("madur") {
            return .elegante
        }
        if folded.contains("diret") || folded.contains("objetiv") || folded.contains("sem enrolar") || folded.contains("sem floreio") {
            return .direto
        }
        if folded.contains("natural") || folded.contains("normal") || folded.contains("conversad") {
            return .natural
        }
        return nil
    }

    private static func inferSubject(from folded: String) -> String? {
        if folded.contains("bolo") && folded.contains("fuba") {
            return "bolo de fubá"
        }
        if folded.contains("codigo") && folded.contains("produto") {
            return "codigo do produto"
        }
        if let recipeSubject = recipeSubject(in: folded) {
            return recipeSubject
        }
        if let recipeSubject = phrase(after: "receita de", in: folded) {
            return recipeSubject
        }
        return nil
    }

    private static func inferRequiredTerms(from folded: String, kind: DraftKind, subject: String?) -> [String] {
        var terms: [String] = []

        if folded.contains("boa noite") {
            terms.append("boa noite")
        }
        if folded.contains("bom dia") {
            terms.append("bom dia")
        }
        if folded.contains("codigo") {
            terms.append("código")
        }
        if folded.contains("produto") {
            terms.append("produto")
        }
        if folded.contains("manha") || folded.contains("amanha") {
            terms.append("amanhã")
        }
        if folded.contains("amo") || folded.contains("ama") {
            terms.append("amo")
        }
        if folded.contains("saudade") {
            terms.append("saudade")
        }
        if folded.contains("estou com saudade") || folded.contains("to com saudade") || folded.contains("tô com saudade") {
            terms.append("estou com saudade")
        }
        if (kind == .reply || kind == .freeform) &&
            (folded.contains("com ele") || folded.contains("pra ele") || folded.contains("para ele") || folded.contains("ver ele") || folded.contains("ve ele")) {
            terms.append("você")
        }
        if kind == .recipe {
            terms.append("ingredientes")
            terms.append("modo de preparo")
        }
        if let subject {
            terms.append(subject)
        }

        return unique(terms)
    }

    private static func inferRequiredGroups(from folded: String, kind: DraftKind) -> [[String]] {
        var groups: [[String]] = []

        if kind == .recipe {
            groups.append(["ingredientes", "lista de ingredientes"])
            groups.append(["modo de preparo", "preparo", "passo a passo"])
            groups.append(["forno", "assar", "asse"])
        }
        if folded.contains("manha") || folded.contains("amanha") {
            groups.append(["amanhã", "de manhã", "pela manhã"])
        }
        if folded.contains("codigo") && folded.contains("produto") {
            groups.append(["código do produto", "codigo do produto"])
        }

        return groups
    }

    private static func clean(_ text: String) -> String {
        var output = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            "\\b(tipo|assim|né|ne|sabe|entendeu|e tal)\\b,?\\s*",
            "\\b(ã+|ah+|hum+|hmm+)\\b,?\\s*"
        ]
        for pattern in patterns {
            output = output.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        while output.contains("  ") {
            output = output.replacingOccurrences(of: "  ", with: " ")
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR")).lowercased()
    }

    private static func phrase(after marker: String, in text: String) -> String? {
        guard let range = text.range(of: marker) else { return nil }
        var phrase = String(text[range.upperBound...])
        let stops = [",", ".", " com ", " completa", " completo", " curta", " curto", " grande", " detalhada", " detalhado"]
        for stop in stops {
            if let stopRange = phrase.range(of: stop) {
                phrase = String(phrase[..<stopRange.lowerBound])
            }
        }
        phrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        return phrase.isEmpty ? nil : phrase
    }

    private static func recipeSubject(in text: String) -> String? {
        guard let recipeRange = text.range(of: "receita") else { return nil }
        var tail = String(text[recipeRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let removable = ["completa", "completo", "curta", "curto", "grande", "detalhada", "detalhado", "rapida", "rapido", "simples"]
        for word in removable {
            if tail.hasPrefix(word) {
                tail.removeFirst(word.count)
                tail = tail.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        guard tail.hasPrefix("de ") else { return nil }
        tail.removeFirst(3)
        let stops = [",", ".", " com ", " para ", " pra ", " e "]
        for stop in stops {
            if let stopRange = tail.range(of: stop) {
                tail = String(tail[..<stopRange.lowerBound])
            }
        }
        tail = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        return tail.isEmpty ? nil : tail
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            let key = fold(value)
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }
}

enum DraftQualityGate {
    static func accepts(_ text: String, intent: DraftIntent) -> Bool {
        let folded = fold(text)

        if intent.length == .long && text.count < 420 {
            return false
        }
        if intent.kind == .reply && intent.length == .medium && intent.mustInclude.count >= 3 && text.count < 110 {
            return false
        }
        if intent.mustInclude.contains(where: { fold($0) == "saudade" }) &&
            intent.mustInclude.contains(where: { fold($0) == "voce" }) &&
            text.count < 55 {
            return false
        }

        for term in intent.mustInclude where !folded.contains(fold(term)) {
            if term == "amo" && (folded.contains("te amo") || folded.contains("também amo")) {
                continue
            }
            return false
        }

        for group in intent.mustIncludeGroups {
            let matched = group.contains { folded.contains(fold($0)) }
            if !matched {
                return false
            }
        }

        if intent.kind == .recipe {
            return folded.contains("ingredientes") && (folded.contains("modo de preparo") || folded.contains("passo a passo"))
        }

        return true
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR")).lowercased()
    }
}

enum SmartLocalComposer {
    static func compose(intent: DraftIntent, tone: ReplyTone) -> String {
        switch intent.kind {
        case .recipe:
            return recipe(intent: intent, tone: tone)
        case .reply:
            return reply(intent: intent, tone: tone)
        case .instruction:
            return instruction(intent: intent, tone: tone)
        case .freeform:
            return freeform(intent: intent, tone: tone)
        }
    }

    private static func reply(intent: DraftIntent, tone: ReplyTone) -> String {
        let folded = fold(intent.cleanedCommand)

        if folded.contains("codigo") && folded.contains("produto") && (folded.contains("manha") || folded.contains("amanha")) {
            return polish(buildReplyFromRequirements(intent: intent), tone: tone)
        }

        if folded.contains("boa noite") && (folded.contains("amo") || folded.contains("ama")) {
            return polish("Também te amo. Boa noite, descansa bem. Amanhã a gente volta a se falar com calma.", tone: tone)
        }

        if let extracted = extractedMessage(from: intent.cleanedCommand) {
            let normalized = normalizeAddressing(extracted)
            return polish(sentence(from: normalized), tone: tone)
        }

        return polish(sentence(from: normalizeAddressing(intent.cleanedCommand)), tone: tone)
    }

    private static func recipe(intent: DraftIntent, tone: ReplyTone) -> String {
        let short = intent.length == .short
        if short {
            return """
            Bolo de fubá rápido: bata 3 ovos, 1 xícara de leite, 1 xícara de óleo, 1 e 1/2 xícara de açúcar, 1 xícara de fubá e 1 xícara de farinha. Misture 1 colher de fermento por último e asse a 180 graus por 35 a 40 minutos.
            """
        }

        if intent.subject != nil && fold(intent.subject ?? "") != "bolo de fuba" {
            let subject = display(intent.subject ?? "receita")
            return """
            Receita completa de \(subject):

            Ingredientes:
            - Ingredientes principais para \(subject)
            - Temperos ou complementos a gosto
            - Sal ou açúcar conforme a receita
            - Água, leite ou outro líquido se a preparação pedir

            Modo de preparo:
            1. Separe todos os ingredientes antes de começar.
            2. Prepare a base da receita com calma, misturando os ingredientes principais.
            3. Ajuste textura, tempero e ponto aos poucos.
            4. Cozinhe, asse ou finalize conforme o tipo de preparo.
            5. Sirva quando estiver no ponto ideal.

            Dica: se quiser, eu adapto essa receita com medidas exatas para a versão que você preferir.
            """
        }

        return """
        Receita completa de bolo de fubá:

        Ingredientes:
        - 3 ovos
        - 1 xícara de leite
        - 1 xícara de óleo
        - 1 e 1/2 xícara de açúcar
        - 1 xícara de fubá
        - 1 xícara de farinha de trigo
        - 1 colher de sopa de fermento em pó
        - Opcional: erva-doce ou queijo ralado

        Modo de preparo:
        1. Preaqueça o forno a 180 graus e unte uma forma média.
        2. Bata os ovos, o leite, o óleo e o açúcar até misturar bem.
        3. Acrescente o fubá e a farinha e bata até a massa ficar lisa.
        4. Misture o fermento por último, delicadamente.
        5. Coloque na forma e asse por 35 a 40 minutos.
        6. Faça o teste do palito: se sair limpo, está pronto.

        Rendimento: cerca de 8 a 10 fatias.
        Dica: para ficar mais molhadinho, substitua metade do leite por leite de coco.
        """
    }

    private static func instruction(intent: DraftIntent, tone: ReplyTone) -> String {
        let text = extractedMessage(from: intent.cleanedCommand).map(sentence(from:)) ?? sentence(from: intent.cleanedCommand)
        return polish(text, tone: tone)
    }

    private static func freeform(intent: DraftIntent, tone: ReplyTone) -> String {
        if let extracted = extractedMessage(from: intent.cleanedCommand) {
            return polish(sentence(from: normalizeAddressing(extracted)), tone: tone)
        }
        return polish(sentence(from: normalizeAddressing(intent.cleanedCommand)), tone: tone)
    }

    private static func extractedMessage(from text: String) -> String? {
        let markers = [
            "responda dizendo que", "responde dizendo que", "responda que", "responde que",
            "responda pra ele que", "responde pra ele que", "responda para ele que", "responde para ele que",
            "diga que", "diga pra ele que", "fale que", "fala pra ele que", "mande que", "manda pra ele que",
            "escreva que", "escreve que", "dizendo que", "falando que"
        ]

        for marker in markers {
            if let range = text.range(of: marker, options: [.caseInsensitive, .diacriticInsensitive]) {
                return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private static func buildReplyFromRequirements(intent: DraftIntent) -> String {
        let folded = fold(intent.cleanedCommand)
        var parts: [String] = []

        if folded.contains("boa noite") {
            parts.append("Boa noite.")
        }
        if folded.contains("amo") || folded.contains("ama") {
            parts.append("Também te amo.")
        }
        if folded.contains("falar") || folded.contains("fala") || folded.contains("convers") || folded.contains("se fala") {
            if folded.contains("manha") || folded.contains("amanha") {
                parts.append("Amanhã de manhã eu falo com você com calma.")
            } else {
                parts.append("Eu falo com você com calma.")
            }
        } else if folded.contains("manha") || folded.contains("amanha") {
            parts.append("Amanhã a gente resolve isso com calma.")
        }
        if folded.contains("codigo") && folded.contains("produto") {
            let timing = (folded.contains("manha") || folded.contains("amanha")) ? "amanhã cedo" : "quando puder"
            parts.append("Também preciso que você me mande o código do produto \(timing), para eu conseguir verificar direitinho.")
        }

        if parts.isEmpty {
            return sentence(from: normalizeAddressing(intent.cleanedCommand))
        }
        return parts.joined(separator: " ")
    }

    private static func normalizeAddressing(_ text: String) -> String {
        var output = text
        let replacements = [
            "com ele": "com você",
            "pra ele": "para você",
            "para ele": "para você",
            "ver ele": "ver você",
            "vê ele": "ver você",
            "ve ele": "ver você",
            "dele": "seu",
            "ele tenha": "você tenha"
        ]
        for (source, target) in replacements {
            output = output.replacingOccurrences(of: source, with: target, options: [.caseInsensitive, .diacriticInsensitive])
        }
        return output
    }

    private static func sentence(from text: String) -> String {
        var output = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["voz mcp", "escreva", "escreve", "mande", "manda", "fale", "fala", "diga"]
        for prefix in prefixes where fold(output).hasPrefix(prefix) {
            output.removeFirst(min(prefix.count, output.count))
            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !output.isEmpty else { return "Me diga melhor o que você quer responder." }
        if let first = output.first {
            output.replaceSubrange(output.startIndex...output.startIndex, with: String(first).uppercased())
        }
        if !output.hasSuffix(".") && !output.hasSuffix("!") && !output.hasSuffix("?") {
            output.append(".")
        }
        return output
    }

    private static func polish(_ text: String, tone: ReplyTone) -> String {
        var output = text
        let replacements = [
            " pra ": " para ",
            " vc ": " você ",
            " tambem ": " também ",
            " amanha ": " amanhã ",
            " codigo ": " código "
        ]
        output = " " + output + " "
        for (source, target) in replacements {
            output = output.replacingOccurrences(of: source, with: target, options: [.caseInsensitive])
        }
        output = output.trimmingCharacters(in: .whitespacesAndNewlines)

        switch tone {
        case .direto:
            return output
                .replacingOccurrences(of: " com calma", with: "", options: [.caseInsensitive])
                .replacingOccurrences(of: " direitinho", with: "", options: [.caseInsensitive])
        case .elegante:
            return output
                .replacingOccurrences(of: "direitinho", with: "corretamente")
                .replacingOccurrences(of: "cedo", with: "pela manhã")
        case .carinhoso:
            if fold(output).contains("saudade") && !fold(output).contains("meu amor") {
                return output.replacingOccurrences(of: ".", with: ", meu amor.", options: [], range: output.range(of: ".", options: .backwards))
            }
            return output
        case .natural:
            return output
        }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR")).lowercased()
    }

    private static func display(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
