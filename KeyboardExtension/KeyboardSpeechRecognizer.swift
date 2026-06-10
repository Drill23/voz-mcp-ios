import AVFoundation
import AVFAudio
import Foundation
import Speech

@MainActor
final class KeyboardSpeechRecognizer {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "pt_BR"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start(onTranscript: @escaping @Sendable (String) -> Void) async throws {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            throw KeyboardSpeechError.speechPermissionDenied
        }

        let microphoneGranted: Bool
        if #available(iOS 17.0, *) {
            microphoneGranted = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        } else {
            microphoneGranted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        guard microphoneGranted else {
            throw KeyboardSpeechError.microphonePermissionDenied
        }

        guard let recognizer, recognizer.isAvailable else {
            throw KeyboardSpeechError.recognizerUnavailable
        }

        task?.cancel()
        task = nil

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                onTranscript(result.bestTranscription.formattedString)
            }

            if error != nil || result?.isFinal == true {
                Task { @MainActor in
                    await self?.stop()
                }
            }
        }
    }

    func stop() async {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

enum KeyboardSpeechError: LocalizedError {
    case speechPermissionDenied
    case microphonePermissionDenied
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .speechPermissionDenied:
            "Permissão de fala negada para o teclado."
        case .microphonePermissionDenied:
            "Permissão de microfone negada para o teclado."
        case .recognizerUnavailable:
            "Reconhecimento de fala local indisponível agora."
        }
    }
}
