import UIKit

final class KeyboardViewController: UIInputViewController {
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let energyGlyph = EnergyGlyphView()
    private let transformButton = UIButton(type: .system)
    private let lengthControl = UISegmentedControl(items: ["Auto", "Curta", "Completa"])
    private let nextButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let prefixButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemBackground
        setup()
        Task { await refreshStatus() }
    }

    private func setup() {
        titleLabel.text = "Voz MCP"
        titleLabel.textColor = .label
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        statusLabel.text = "Dite no campo e transforme aqui."
        statusLabel.textColor = .secondaryLabel
        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.numberOfLines = 2
        statusLabel.textAlignment = .left

        configureIcon(deleteButton, symbol: "delete.left", action: #selector(deleteBackward), label: "Apagar")
        configureIcon(nextButton, symbol: "globe", action: #selector(advanceKeyboard), label: "Trocar teclado")

        let topRow = UIStackView(arrangedSubviews: [titleLabel, UIView(), deleteButton, nextButton])
        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.spacing = 8

        energyGlyph.translatesAutoresizingMaskIntoConstraints = false

        configureTransformButton()
        transformButton.addTarget(self, action: #selector(transformHostField), for: .touchUpInside)

        let actionRow = UIStackView(arrangedSubviews: [energyGlyph, transformButton])
        actionRow.axis = .horizontal
        actionRow.alignment = .center
        actionRow.spacing = 10

        lengthControl.selectedSegmentIndex = 0
        lengthControl.selectedSegmentTintColor = .label
        lengthControl.setTitleTextAttributes(
            [.foregroundColor: UIColor.systemBackground, .font: UIFont.systemFont(ofSize: 11, weight: .bold)],
            for: .selected
        )
        lengthControl.setTitleTextAttributes(
            [.foregroundColor: UIColor.secondaryLabel, .font: UIFont.systemFont(ofSize: 11, weight: .semibold)],
            for: .normal
        )

        configurePrefixButton()
        prefixButton.addTarget(self, action: #selector(insertPrefix), for: .touchUpInside)

        let bottomRow = UIStackView(arrangedSubviews: [lengthControl, prefixButton])
        bottomRow.axis = .horizontal
        bottomRow.alignment = .center
        bottomRow.spacing = 8
        bottomRow.distribution = .fill

        let content = UIStackView(arrangedSubviews: [topRow, statusLabel, actionRow, bottomRow])
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 8
        view.addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            energyGlyph.widthAnchor.constraint(equalToConstant: 42),
            energyGlyph.heightAnchor.constraint(equalToConstant: 42),
            transformButton.heightAnchor.constraint(equalToConstant: 46),
            deleteButton.widthAnchor.constraint(equalToConstant: 36),
            nextButton.widthAnchor.constraint(equalToConstant: 36),
            prefixButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 118),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 158)
        ])
    }

    private func refreshStatus() async {
        let status = await DraftGenerator().modelStatus()
        await MainActor.run {
            statusLabel.text = status.isReady ? "IA local da Apple pronta. O texto será inserido no campo ativo." : "IA Apple indisponível agora. Uso composição local inteligente."
        }
    }

    @objc private func transformHostField() {
        let beforeInput = textDocumentProxy.documentContextBeforeInput ?? ""
        guard let command = extractCommand(from: beforeInput) else {
            if beforeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textDocumentProxy.insertText("voz mcp ")
                statusLabel.text = "Dite seu pedido depois de voz mcp."
            } else {
                statusLabel.text = "Use: voz mcp responda dizendo que..."
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
        statusLabel.text = "Agora dite ou escreva o pedido."
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
            setWorking(true)
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
            statusLabel.text = "\(result.engine.title). Inserido no campo."
            setWorking(false)
        }
    }

    private func setWorking(_ working: Bool) {
        transformButton.isEnabled = !working
        prefixButton.isEnabled = !working
        energyGlyph.setActive(working)
        var configuration = transformButton.configuration
        configuration?.title = working ? "Transformando" : "Transformar"
        configuration?.showsActivityIndicator = working
        transformButton.configuration = configuration
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

    private func extractCommand(from context: String) -> KeyboardCommandExtraction? {
        KeyboardCommandParser.extract(from: context)
    }

    private func configureTransformButton() {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Transformar"
        configuration.image = UIImage(systemName: "sparkles")
        configuration.imagePadding = 7
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = .label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        transformButton.configuration = configuration
        transformButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        transformButton.accessibilityLabel = "Transformar pedido em mensagem"
    }

    private func configurePrefixButton() {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = "voz mcp"
        configuration.image = UIImage(systemName: "text.cursor")
        configuration.imagePadding = 5
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .label
        configuration.baseBackgroundColor = .secondarySystemFill
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        prefixButton.configuration = configuration
        prefixButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        prefixButton.accessibilityLabel = "Inserir comando Voz MCP"
    }

    private func configureIcon(_ button: UIButton, symbol: String, action: Selector, label: String) {
        var configuration = UIButton.Configuration.tinted()
        configuration.image = UIImage(systemName: symbol)
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .label
        configuration.baseBackgroundColor = .secondarySystemFill
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8)
        button.configuration = configuration
        button.accessibilityLabel = label
        button.addTarget(self, action: action, for: .touchUpInside)
    }
}

final class EnergyGlyphView: UIView {
    private let gradientLayer = CAGradientLayer()
    private let glassLayer = CALayer()
    private let symbolView = UIImageView(image: UIImage(systemName: "waveform"))

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false

        gradientLayer.type = .conic
        gradientLayer.colors = [
            UIColor.systemCyan.cgColor,
            UIColor.systemMint.cgColor,
            UIColor.white.cgColor,
            UIColor.systemOrange.cgColor,
            UIColor.systemPink.cgColor,
            UIColor.systemCyan.cgColor
        ]
        layer.addSublayer(gradientLayer)

        glassLayer.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.88).cgColor
        layer.addSublayer(glassLayer)

        symbolView.tintColor = .label
        symbolView.contentMode = .scaleAspectFit
        addSubview(symbolView)

        layer.shadowColor = UIColor.systemCyan.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 10
        layer.shadowOffset = .zero
        startAnimation()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        gradientLayer.cornerRadius = bounds.width / 2
        glassLayer.frame = bounds.insetBy(dx: 4, dy: 4)
        glassLayer.cornerRadius = glassLayer.bounds.width / 2
        symbolView.frame = bounds.insetBy(dx: 12, dy: 12)
    }

    func setActive(_ active: Bool) {
        layer.shadowOpacity = active ? 0.34 : 0.18
        layer.shadowRadius = active ? 18 : 10
        symbolView.image = UIImage(systemName: active ? "waveform" : "sparkles")
    }

    private func startAnimation() {
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = Double.pi * 2
        rotation.duration = 6
        rotation.repeatCount = .infinity
        gradientLayer.add(rotation, forKey: "rotation")

        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 0.98
        pulse.toValue = 1.03
        pulse.duration = 1.2
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        layer.add(pulse, forKey: "pulse")
    }
}
