//
//  SpeechRecognizerService.swift
//  nano ewallet
//
//  Nhận diện giọng nói tiếng Việt — tương ứng `rememberVoiceInput` bên Android.
//  Android dùng SpeechRecognizer của hệ thống, iOS dùng Speech framework
//  (SFSpeechRecognizer + AVAudioEngine).
//
//  Cần NSMicrophoneUsageDescription + NSSpeechRecognitionUsageDescription trong
//  Info.plist (đã có).
//

import Foundation
import Combine
import Speech
import AVFoundation

@MainActor
final class SpeechRecognizerService: ObservableObject {

    @Published private(set) var isListening = false
    /// Chuỗi nghe được theo thời gian thực — hiện lên để người dùng biết máy đang bắt gì.
    @Published private(set) var partialText = ""
    @Published private(set) var errorMessage: String?

    /// Các phương án nhận diện của lượt vừa xong. Nhiều phương án giúp bóc số tiền
    /// chính xác hơn (chọn giá trị lặp lại nhiều nhất).
    var onResult: (([String]) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "vi-VN"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Tự dừng khi im lặng — recognizer của iOS không tự chốt như Android.
    private var silenceTimer: Timer?

    /// Nhận diện tiếng Việt có dùng được LÚC NÀY không.
    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    /// Lý do không dùng được — `SFSpeechRecognizer.isAvailable` chỉ trả true/false chứ
    /// KHÔNG nói vì sao, nên phải tự suy ra. Ghi cứng một lý do là đổ lỗi nhầm: trên
    /// simulator mạng vẫn tốt mà vẫn `false`.
    var unavailableReason: String {
        #if targetEnvironment(simulator)
        // Tiếng Việt không có model offline (supportsOnDeviceRecognition = false) nên
        // bắt buộc qua máy chủ Apple, mà simulator không được cấp quyền đó.
        return "Simulator không chạy được nhận diện giọng nói tiếng Việt. Cần thử trên máy thật."
        #else
        return recognizer == nil
            ? "Máy chưa hỗ trợ nhận diện giọng nói tiếng Việt."
            : "Giọng nói đang không dùng được. Kiểm tra kết nối mạng rồi thử lại."
        #endif
    }

    func start() async {
        guard !isListening else { return }
        errorMessage = nil
        partialText = ""

        guard isAvailable else {
            errorMessage = unavailableReason
            return
        }
        guard await requestPermissions() else { return }

        do {
            try beginSession()
            isListening = true
        } catch {
            errorMessage = "Không mở được micro, vui lòng thử lại."
            stop()
        }
    }

    func stop() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Private

    private func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            errorMessage = "Cần quyền nhận diện giọng nói. Bật lại trong Cài đặt iOS."
            return false
        }

        let micGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard micGranted else {
            errorMessage = "Cần quyền micro để dùng giọng nói."
            return false
        }
        return true
    }

    private func beginSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let inputNode = audioEngine.inputNode
        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.partialText = result.bestTranscription.formattedString
                    self.restartSilenceTimer()
                    if result.isFinal {
                        self.finish(with: result)
                    }
                } else if error != nil {
                    // Hết thời gian chờ / không nghe được — chốt bằng phần đã nghe.
                    self.finishWithPartial()
                }
            }
        }

        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        restartSilenceTimer()
    }

    /// iOS chỉ chốt `isFinal` khi hết audio, mà micro thì chạy mãi. Im lặng ~1,6s coi
    /// như nói xong — nếu không người dùng phải tự bấm dừng.
    private func restartSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finishWithPartial() }
        }
    }

    private func finish(with result: SFSpeechRecognitionResult) {
        // Nhiều phương án: `transcriptions` khi có, thiếu thì dùng bản tốt nhất.
        var candidates = result.transcriptions.map(\.formattedString)
        if candidates.isEmpty { candidates = [result.bestTranscription.formattedString] }
        stop()
        onResult?(candidates.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    private func finishWithPartial() {
        let heard = partialText.trimmingCharacters(in: .whitespaces)
        stop()
        onResult?(heard.isEmpty ? [] : [heard])
    }
}
