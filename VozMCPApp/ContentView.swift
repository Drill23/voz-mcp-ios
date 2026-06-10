import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = ComposerViewModel()
    @FocusState private var focusedField: ComposerField?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    statusStrip
                    voiceControl
                    examplesStrip
                    composerPanel
                    outputPanel
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .background(AppBackdrop().ignoresSafeArea())
            .navigationTitle("Voz MCP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Ajustes")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.clear()
                        focusedField = nil
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .accessibilityLabel("Limpar")
                }
            }
        }
        .task {
            await viewModel.refreshModelStatus()
        }
    }

    private var statusStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: viewModel.modelStatus.isReady ? "checkmark.seal.fill" : "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(viewModel.modelStatus.isReady ? .green : .blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.modelStatus.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(viewModel.statusLine ?? viewModel.modelStatus.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var voiceControl: some View {
        VStack(spacing: 12) {
            LiquidVoiceButton(isActive: viewModel.isRecording || viewModel.isGenerating) {
                Task { await viewModel.toggleRecording() }
            }

            Text(viewModel.isRecording ? "Ouvindo" : "Toque e fale")
                .font(.title2.weight(.semibold))
                .lineLimit(1)

            Text(viewModel.isRecording ? "Toque de novo para parar." : "Transforme voz em uma mensagem pronta.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }

    private var examplesStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ComposerExample.samples) { example in
                    Button {
                        viewModel.useExample(example)
                        focusedField = .command
                    } label: {
                        Label(example.title, systemImage: example.systemImage)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 9)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(.primary.opacity(0.07), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var composerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pedido")
                .font(.headline)

            PromptEditor(
                text: $viewModel.commandText,
                placeholder: "Ex: responda dizendo que amanhã cedo eu preciso do código do produto"
            )
            .focused($focusedField, equals: .command)
            .frame(minHeight: 120)

            Picker("Tom", selection: $viewModel.tone) {
                ForEach(ReplyTone.allCases) { tone in
                    Text(tone.title).tag(tone)
                }
            }
            .pickerStyle(.segmented)

            Button {
                focusedField = nil
                Task { await viewModel.generateDraft() }
            } label: {
                Label(viewModel.isGenerating ? "Gerando" : "Gerar mensagem", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(viewModel.isGenerating)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var outputPanel: some View {
        if !viewModel.draftText.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Mensagem")
                        .font(.headline)
                    Spacer()
                    Text(viewModel.lastEngine?.title ?? "Pronta")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                PromptEditor(text: $viewModel.draftText, placeholder: "")
                    .focused($focusedField, equals: .draft)
                    .frame(minHeight: 170)

                HStack(spacing: 10) {
                    Button {
                        viewModel.copyDraft()
                    } label: {
                        Label("Copiar", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryActionButtonStyle())

                    Button {
                        viewModel.shareDraft()
                    } label: {
                        Label("Enviar", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.primary.opacity(0.06), lineWidth: 1)
            }
        }
    }
}

private enum ComposerField {
    case command
    case draft
}

private struct AppBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)

            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.08, green: 0.10, blue: 0.13).opacity(0.95),
                        Color(red: 0.00, green: 0.42, blue: 0.48).opacity(0.22),
                        Color(red: 0.70, green: 0.18, blue: 0.35).opacity(0.16)
                    ]
                    : [
                        Color.white.opacity(0.92),
                        Color(red: 0.78, green: 0.95, blue: 0.96).opacity(0.55),
                        Color(red: 1.00, green: 0.88, blue: 0.78).opacity(0.40)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct LiquidVoiceButton: View {
    let isActive: Bool
    let action: () -> Void

    @State private var rotation = 0.0
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle()
                            .stroke(.primary.opacity(0.08), lineWidth: 1)
                    }

                Circle()
                    .trim(from: 0.08, to: 0.92)
                    .stroke(
                        AngularGradient(
                            colors: [.cyan, .mint, .white, .orange, .pink, .cyan],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(rotation))
                    .padding(5)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(isActive ? 0.34 : 0.20),
                                .cyan.opacity(isActive ? 0.20 : 0.12),
                                .clear
                            ],
                            center: .topLeading,
                            startRadius: 2,
                            endRadius: 72
                        )
                    )
                    .padding(15)

                Image(systemName: isActive ? "waveform" : "mic.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
            }
            .frame(width: 124, height: 124)
            .scaleEffect(isActive && pulse ? 1.04 : 1)
            .shadow(color: .cyan.opacity(isActive ? 0.28 : 0.14), radius: isActive ? 28 : 16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "Parar gravação" : "Iniciar gravação")
        .onAppear {
            withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct PromptEditor: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .tint(.cyan)
            .scrollContentBackground(.hidden)
            .padding(10)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.primary.opacity(0.07), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                if text.isEmpty && !placeholder.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
    }
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.74 : 1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .foregroundStyle(.primary)
            .padding(.vertical, 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.primary.opacity(configuration.isPressed ? 0.12 : 0.06), lineWidth: 1)
            }
    }
}
