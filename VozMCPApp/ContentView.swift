import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = ComposerViewModel()
    @FocusState private var focusedField: ComposerField?

    var body: some View {
        ZStack {
            CleanBackdrop()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    header
                    orbSection
                    composer
                    resultSection
                    statusSection
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await viewModel.refreshModelStatus()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Voz MCP")
                    .font(.headline.weight(.semibold))
                Text("teclado inteligente local")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.56))
            }

            Spacer()

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(IconGlassButtonStyle())
        }
    }

    private var orbSection: some View {
        VStack(spacing: 14) {
            SiriOrb(isActive: viewModel.isRecording || viewModel.isGenerating)
                .frame(width: 176, height: 176)
                .onTapGesture {
                    Task { await viewModel.toggleRecording() }
                }

            VStack(spacing: 5) {
                Text(viewModel.isRecording ? "Ouvindo" : "Fale seu pedido")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.82)

                Text(viewModel.isRecording ? "Toque de novo para parar e gerar." : "Ou dite direto no WhatsApp e use o teclado para transformar.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 330)
            }
        }
        .padding(.top, 6)
    }

    private var composer: some View {
        VStack(spacing: 12) {
            PromptEditor(
                text: $viewModel.commandText,
                placeholder: "Ex: responda dizendo que falo com ele pela manhã, dê boa noite e peça o código do produto amanhã cedo"
            )
            .focused($focusedField, equals: .command)
            .frame(minHeight: 112)

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
                Label(viewModel.isGenerating ? "Gerando..." : "Gerar texto", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryGlassButtonStyle())
            .disabled(viewModel.isGenerating)
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if !viewModel.draftText.isEmpty {
            VStack(spacing: 12) {
                PromptEditor(text: $viewModel.draftText, placeholder: "")
                    .focused($focusedField, equals: .draft)
                    .frame(minHeight: 142)

                HStack(spacing: 10) {
                    Button {
                        viewModel.copyDraft()
                    } label: {
                        Label("Copiar", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(QuietGlassButtonStyle())

                    Button {
                        viewModel.shareDraft()
                    } label: {
                        Label("Enviar", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(QuietGlassButtonStyle())
                }
            }
        }
    }

    private var statusSection: some View {
        VStack(spacing: 8) {
            Text(viewModel.statusLine ?? viewModel.modelStatus.detail)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }
}

private enum ComposerField {
    case command
    case draft
}

private struct CleanBackdrop: View {
    var body: some View {
        Color(red: 0.02, green: 0.025, blue: 0.032)
            .overlay {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color(red: 0.02, green: 0.64, blue: 0.68).opacity(0.11),
                        Color(red: 0.95, green: 0.28, blue: 0.40).opacity(0.08),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
    }
}

private struct SiriOrb: View {
    let isActive: Bool
    @State private var rotate = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }

            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(red: 0.10, green: 0.92, blue: 0.95),
                            .white,
                            Color(red: 0.98, green: 0.62, blue: 0.18),
                            Color(red: 0.92, green: 0.25, blue: 0.52),
                            Color(red: 0.10, green: 0.92, blue: 0.95)
                        ],
                        center: .center
                    ),
                    lineWidth: isActive ? 8 : 6
                )
                .rotationEffect(.degrees(rotate ? 360 : 0))
                .padding(4)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(isActive ? 0.26 : 0.18),
                            Color(red: 0.08, green: 0.12, blue: 0.15).opacity(0.62),
                            .black.opacity(0.18)
                        ],
                        center: .topLeading,
                        startRadius: 8,
                        endRadius: 92
                    )
                )
                .padding(15)

            Image(systemName: isActive ? "waveform" : "mic.fill")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.white)
        }
        .scaleEffect(isActive && pulse ? 1.035 : 1)
        .shadow(color: .cyan.opacity(isActive ? 0.32 : 0.18), radius: isActive ? 34 : 22)
        .onAppear {
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                rotate = true
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
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
            .foregroundStyle(.white)
            .tint(.cyan)
            .scrollContentBackground(.hidden)
            .padding(13)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                if text.isEmpty && !placeholder.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.34))
                        .padding(.horizontal, 19)
                        .padding(.vertical, 21)
                        .allowsHitTesting(false)
                }
            }
    }
}

private struct PrimaryGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.vertical, 15)
            .background(.white.opacity(configuration.isPressed ? 0.74 : 0.94), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct QuietGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.vertical, 12)
            .background(.white.opacity(configuration.isPressed ? 0.08 : 0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct IconGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .background(.white.opacity(configuration.isPressed ? 0.08 : 0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
