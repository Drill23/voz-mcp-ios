import UIKit

final class KeyboardViewController: UIInputViewController {
    private let statusLabel = UILabel()
    private let orb = SiriTransformControl()
    private let lengthControl = UISegmentedControl(items: ["Auto", "Curto", "Completo"])
    private let nextButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let prefixButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.018, green: 0.020, blue: 0.026, alpha: 1)
        setup()
        Task { await refreshStatus() }
    }

    private func setup() {
        let title = UILabel()
        title.text = "Voz MCP"
        title.textColor = .white
        title.font = .systemFont(ofSize: 15, weight: .semibold)

        statusLabel.text = "Dite no campo e toque no orbe."
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.58)
        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.numberOfLines = 2
        statusLabel.textAlignment = .right

        configureIcon(deleteButton, symbol: "delete.left", action: #selector(deleteBackward), label: "Apagar")
        configureIcon(nextButton, symbol: "globe", action: #selector(advanceKeyboard), label: "Trocar teclado")

        let topRow = UIStackView(arrangedSubviews: [title, spacer(), deleteButton, nextButton])
        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.spacing = 8

        orb.addTarget(self, action: #selector(transformHostField), for: .touchUpInside)
        orb.translatesAutoresizingMaskIntoConstraints = false

        let orbColumn = UIStackView(arrangedSubviews: [orb])
        orbColumn.axis = .vertical
        orbColumn.alignment = .center

        let middle = UIStackView(arrangedSubviews: [orbColumn, statusLabel])
        middle.axis = .horizontal
        middle.alignment = .center
        middle.spacing = 16

        lengthControl.selectedSegmentIndex = 0
        lengthControl.selectedSegmentTintColor = UIColor.white.withAlphaComponent(0.92)
        lengthControl.setTitleTextAttributes([.foregroundColor: UIColor.black, .font: UIFont.systemFont(ofSize: 11, weight: .bold)], for: .selected)
        lengthControl.setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.68), .font: UIFont.systemFont(ofSize: 11, weight: .semibold)], for: .normal)

        configurePill(prefixButton, title: "Inserir comando", symbol: "text.cursor", action: #selector(insertPrefix))

        let bottomRow = UIStackView(arrangedSubviews: [lengthControl, prefixButton])
        bottomRow.axis = .horizontal
        bottomRow.alignment = .center
        bottomRow.spacing = 8
        bottomRow.distribution = .fillProportionally

        let stack = UIStackView(arrangedSubviews: [topRow, middle, bottomRow])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 10
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            orb.widthAnchor.constraint(equalToConstant: 92),
            orb.heightAnchor.constraint(equalToConstant: 92),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 176)
        ])
    }

    private func refreshStatus() async {
        let status = await DraftGenerator().modelStatus()
        await MainActor.run {
            statusLabel.text = status.isReady ? "IA local pronta.\nTransforme o campo." : "\(status.title)\nUso composição local se precisar."
        }
    }

    @objc private func transformHostField() {
        let beforeInput = textDocumentProxy.documentContextBeforeInput ?? ""
        guard let command = extractCommand(from: beforeInput) else {
            if beforeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textDocumentProxy.insertText("voz mcp ")
                statusLabel.text = "Agora dite o pedido\nno campo do app."
            } else {
                statusLabel.text = "Inclua o pedido no campo:\nvoz mcp escreva..."
            }
            return
        }

        Task {
            await insertGenerated(
                command: command.text,
                context: beforeInput,
                charactersToDelete: command.charactersToDelete
            )
        }
    }

    @objc private func insertPrefix() {
        textDocumentProxy.insertText("voz mcp ")
        statusLabel.text = "Dite seu pedido depois\ndesse comando."
    }

    @objc private func deleteBackward() {
        textDocumentProxy.deleteBackward()
    }

    @objc private func advanceKeyboard() {
        advanceToNextInputMode()
    }

    private func insertGenerated(command: String, context: String, charactersToDelete: Int) async {
        await MainActor.run {
            statusLabel.text = "Transformando..."
            orb.setWorking(true)
            orb.isEnabled = false
            prefixButton.isEnabled = false
        }

        let request = DraftRequest(command: sized(command), context: context, tone: .natural)
        let result = await DraftGenerator().generate(request)

        await MainActor.run {
            if charactersToDelete > 0 {
                for _ in 0..<charactersToDelete {
                    textDocumentProxy.deleteBackward()
                }
            }
            textDocumentProxy.insertText(result.text)
            orb.isEnabled = true
            prefixButton.isEnabled = true
            orb.setWorking(false)
            statusLabel.text = "\(result.engine.title)\nInserido no campo."
        }
    }

    private func sized(_ command: String) -> String {
        switch lengthControl.selectedSegmentIndex {
        case 1:
            return "Responda de forma curta. \(command)"
        case 2:
            return "Responda de forma completa e detalhada. \(command)"
        default:
            return command
        }
    }

    private func extractCommand(from context: String) -> (text: String, charactersToDelete: Int)? {
        let triggers = ["voz mcp", "vos mcp", "vós mcp", "mcp"]
        for trigger in triggers {
            if let range = context.range(of: trigger, options: [.caseInsensitive, .diacriticInsensitive, .backwards]) {
                let rawCommand = String(context[range.lowerBound...])
                let command = String(context[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !command.isEmpty else { return nil }
                return (command, rawCommand.count)
            }
        }

        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 420 else { return nil }
        if trimmed.range(of: "escrev", options: [.caseInsensitive, .diacriticInsensitive]) != nil ||
            trimmed.range(of: "respond", options: [.caseInsensitive, .diacriticInsensitive]) != nil ||
            trimmed.range(of: "manda", options: [.caseInsensitive, .diacriticInsensitive]) != nil ||
            trimmed.range(of: "diga", options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return (trimmed, context.count)
        }

        return nil
    }

    private func configureIcon(_ button: UIButton, symbol: String, action: Selector, label: String) {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: symbol)
        configuration.cornerStyle = .large
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = UIColor.white.withAlphaComponent(0.10)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        button.configuration = configuration
        button.accessibilityLabel = label
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func configurePill(_ button: UIButton, title: String, symbol: String, action: Selector) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePadding = 5
        configuration.cornerStyle = .large
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = UIColor.white.withAlphaComponent(0.10)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        button.configuration = configuration
        button.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func spacer() -> UIView {
        let view = UIView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }
}

final class SiriTransformControl: UIControl {
    private let gradientLayer = CAGradientLayer()
    private let glassLayer = CALayer()
    private let symbolView = UIImageView(image: UIImage(systemName: "sparkles"))

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityLabel = "Transformar texto"

        gradientLayer.type = .conic
        gradientLayer.colors = [
            UIColor.systemCyan.cgColor,
            UIColor.white.cgColor,
            UIColor.systemOrange.cgColor,
            UIColor.systemPink.cgColor,
            UIColor.systemMint.cgColor,
            UIColor.systemCyan.cgColor
        ]
        layer.addSublayer(gradientLayer)

        glassLayer.backgroundColor = UIColor(red: 0.025, green: 0.034, blue: 0.045, alpha: 0.88).cgColor
        layer.addSublayer(glassLayer)

        symbolView.tintColor = .white
        symbolView.contentMode = .scaleAspectFit
        addSubview(symbolView)

        layer.shadowColor = UIColor.systemCyan.cgColor
        layer.shadowOpacity = 0.26
        layer.shadowRadius = 22
        layer.shadowOffset = .zero
        startIdleAnimation()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        gradientLayer.cornerRadius = bounds.width / 2
        glassLayer.frame = bounds.insetBy(dx: 8, dy: 8)
        glassLayer.cornerRadius = glassLayer.bounds.width / 2
        symbolView.frame = bounds.insetBy(dx: 31, dy: 31)
    }

    func setWorking(_ working: Bool) {
        symbolView.image = UIImage(systemName: working ? "waveform" : "sparkles")
        layer.shadowOpacity = working ? 0.42 : 0.26
        layer.shadowRadius = working ? 30 : 22
        startIdleAnimation()
    }

    private func startIdleAnimation() {
        if gradientLayer.animation(forKey: "rotation") == nil {
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0
            rotation.toValue = Double.pi * 2
            rotation.duration = 7
            rotation.repeatCount = .infinity
            gradientLayer.add(rotation, forKey: "rotation")
        }

        if layer.animation(forKey: "pulse") == nil {
            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = 0.985
            pulse.toValue = 1.025
            pulse.duration = 1.25
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            layer.add(pulse, forKey: "pulse")
        }
    }
}
