import AVFoundation
import Speech
import SwiftUI

/// Speech to text with the phone's own recognizer: the words appear while the user talks.
@MainActor
final class Dictation: ObservableObject {
    @Published private(set) var listening = false
    /// How loud it is now, 0...1, for the button to breathe with.
    @Published private(set) var level: CGFloat = 0
    @Published var problem: String?

    /// Gets everything heard so far, whole each time.
    var onText: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))

    func start() async {
        guard !listening else { return }
        problem = nil
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else {
            problem = "没有语音识别权限，去 设置 → 隐私与安全性 → 语音识别 里打开。"
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            problem = "没有麦克风权限，去 设置 → 隐私与安全性 → 麦克风 里打开。"
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            problem = "语音识别现在用不了，稍后再试。"
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            self.request = request
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0), block: Self.tap(request) { [weak self] level in
                Task { @MainActor in self?.level = level }
            })
            engine.prepare()
            try engine.start()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { listening = true }
            task = recognizer.recognitionTask(with: request, resultHandler: Self.results { [weak self] text, done in
                Task { @MainActor in
                    if let text { self?.onText?(text) }
                    if done { self?.finish() }
                }
            })
        } catch {
            problem = "开不了麦克风：\(error.localizedDescription)"
            finish()
        }
    }

    /// Stops listening; the last words still arrive.
    func stop() {
        request?.endAudio()
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        withAnimation(.smooth) {
            listening = false
            level = 0
        }
    }

    private func finish() {
        stop()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Runs on the audio thread: feeds the recognizer and measures loudness.
    nonisolated private static func tap(_ request: SFSpeechAudioBufferRecognitionRequest, level: @escaping @Sendable (CGFloat) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            request.append(buffer)
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var sum: Float = 0
            for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
            let rms = sqrt(sum / Float(buffer.frameLength))
            level(CGFloat(min(1, max(0, (20 * log10(max(rms, 0.000_01)) + 50) / 40))))
        }
    }

    nonisolated private static func results(_ report: @escaping @Sendable (String?, Bool) -> Void) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            report(result?.bestTranscription.formattedString, error != nil || result?.isFinal == true)
        }
    }
}
