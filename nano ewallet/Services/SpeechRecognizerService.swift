//
//  SpeechRecognizerService.swift
//  nano ewallet
//
//  Nhận diện giọng nói tiếng Việt — tương ứng `rememberVoiceInput` bên Android.
//
//  HAI ENGINE, chọn theo phiên bản máy (deployment target của app là 16.0):
//
//   - iOS 26+: `SpeechAnalyzer` + `DictationTranscriber` — chạy hoàn toàn ON-DEVICE cho
//     `vi_VN`, không round-trip mạng nên bắt số tiền nhạy hơn hẳn. Đây là engine ưu tiên.
//   - iOS 16-25: `SFSpeechRecognizer` — tiếng Việt KHÔNG có model on-device
//     (`supportsOnDeviceRecognition == false` cho `vi-VN`) nên mọi lượt nghe phải qua server
//     Apple, có độ trễ mạng. Đây là giới hạn của nền tảng, không phải thiếu sót cấu hình.
//
//  Cả hai engine chia sẻ: bộ đếm im lặng 0.8s (mirror
//  `EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS` bên Android), từ vựng gợi ý số tiền, và
//  giao diện công khai (`start`/`stop`/`onResult`/`partialText`/`isListening`) — 3 màn gọi
//  (`WalletTransferAmountView`/`BankTransferView`/`VoiceCommandOverlay`) không cần biết engine nào.
//
//  Cần NSMicrophoneUsageDescription + NSSpeechRecognitionUsageDescription trong Info.plist.
//

import Foundation
import Combine
import Speech
import AVFoundation

/// Từ vựng gợi ý cho engine — mirror `EXTRA_BIASING_STRINGS` bên Android. Engine ưu tiên khớp
/// các từ này khi phân vân, giảm nghe nhầm số/đơn vị tiếng Việt ("trăm" -> "trăng").
private let amountBiasingStrings = [
    "không", "một", "hai", "ba", "bốn", "tư", "năm", "lăm", "sáu", "bảy", "tám", "chín",
    "mười", "mươi", "trăm", "nghìn", "ngàn", "triệu", "tỷ", "rưỡi", "lẻ", "linh",
    "chuyển", "đồng",
]

/// Khoảng lặng SAU KHI ĐÃ NÓI thì coi là dứt câu — 0.8s, mirror
/// `EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS` bên Android, đã kiểm chứng ổn với câu
/// chuyển tiền tiếng Việt (ngắn, kiểu "chuyển hai trăm nghìn"). Chờ lâu hơn không chỉ chậm mà
/// còn dễ lẫn tạp âm vào ngay trước lúc chốt kết quả.
private let silenceInterval: TimeInterval = 0.8

/// Thời gian chờ người dùng BẮT ĐẦU nói, tính từ lúc mic mở — dài hơn hẳn `silenceInterval`.
///
/// Hai mốc này KHÁC BẢN CHẤT, dùng chung một giá trị là sai: 0.8s tính từ lúc bật mic thì
/// người dùng chưa kịp đưa máy lên miệng đã bị ngắt. Android cũng tách riêng
/// (`EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS`), không dùng lại mốc lặng cuối câu.
private let initialSpeechTimeout: TimeInterval = 6.0

private let speechLocale = Locale(identifier: "vi-VN")

@MainActor
final class SpeechRecognizerService: ObservableObject {

    @Published private(set) var isListening = false
    /// Chuỗi nghe được theo thời gian thực — hiện lên để người dùng biết máy đang bắt gì.
    @Published private(set) var partialText = ""
    @Published private(set) var errorMessage: String?

    /// Các phương án nhận diện của lượt vừa xong. Engine mới chỉ trả 1 bản text; engine cũ
    /// (`SFSpeechRecognizer`) trả nhiều phương án, giúp bóc số tiền chính xác hơn.
    var onResult: (([String]) -> Void)?

    private let audioEngine = AVAudioEngine()

    /// Tự dừng khi im lặng — cả hai engine đều không tự chốt như Android.
    private var silenceTimer: Timer?
    /// Lượt nghe này đã trả kết quả chưa — chặn `stop()`/silence timer bắn `onResult` hai lần.
    private var hasDelivered = false

    // Engine mới (iOS 26+). Không thể khai kiểu tường minh vì kiểu đó chỉ tồn tại từ iOS 26 —
    // giữ dưới dạng `Any?` rồi ép kiểu trong nhánh `@available`.
    private var modernSession: Any?
    // Engine cũ (iOS 15-25).
    private var legacyRecognizer: SFSpeechRecognizer?
    private var legacyRequest: SFSpeechAudioBufferRecognitionRequest?
    private var legacyTask: SFSpeechRecognitionTask?

    /// Nhận diện tiếng Việt có dùng được LÚC NÀY không.
    ///
    /// Engine mới không có API đồng bộ để kiểm tra (phải `await supportedLocales`), nên trước
    /// lượt `start()` đầu tiên chỗ này lạc quan (`true`) rồi `start()` tự set `errorMessage`
    /// nếu hoá ra không dùng được. Engine cũ thì kiểm tra được ngay.
    var isAvailable: Bool {
        if #available(iOS 26.0, *) { return isModernAvailable }
        return SFSpeechRecognizer(locale: speechLocale)?.isAvailable ?? false
    }

    private var isModernAvailable = true

    var unavailableReason: String {
        if let errorMessage { return errorMessage }
        #if targetEnvironment(simulator)
        // Tiếng Việt không có model offline trên engine cũ nên bắt buộc qua máy chủ Apple, mà
        // simulator không được cấp quyền đó.
        return "Simulator không chạy được nhận diện giọng nói tiếng Việt. Cần thử trên máy thật."
        #else
        return "Giọng nói đang không dùng được. Kiểm tra kết nối mạng rồi thử lại."
        #endif
    }

    // MARK: - Vòng đời

    func start() async {
        guard !isListening else { return }
        errorMessage = nil
        partialText = ""
        hasDelivered = false

        guard await requestPermissions() else { return }

        do {
            if #available(iOS 26.0, *) {
                try await startModern()
            } else {
                try startLegacy()
            }
            isListening = true
            // Mốc DÀI cho lần hẹn đầu: đây là "chờ bắt đầu nói", không phải "khoảng lặng cuối
            // câu". Dùng `silenceInterval` ở đây thì mic tự tắt sau 0.8s dù người dùng chưa
            // kịp mở miệng.
            restartSilenceTimer(timeout: initialSpeechTimeout)
        } catch {
            if #available(iOS 26.0, *) { isModernAvailable = false }
            errorMessage = Self.message(for: error)
            teardown()
        }
    }

    /// Tải trước model nhận diện on-device (chỉ iOS 26+), gọi lúc app đã vào Home.
    ///
    /// Engine mới cần model `vi-VN` có sẵn trên máy mới nghe được. Lần đầu tải có thể mất vài
    /// giây tới vài chục giây tuỳ mạng — nếu để tới lúc người dùng bấm mic mới tải thì họ thấy
    /// mic "không phản hồi" mà không hiểu vì sao. Gọi trước ở nền để tới lúc cần đã sẵn.
    ///
    /// An toàn gọi nhiều lần: `ensureModelReady` cache bằng `Task` tĩnh nên chỉ tải đúng 1 lần.
    /// Không throw, không set `errorMessage` — thất bại thì im lặng, `start()` sẽ tự báo lỗi
    /// lúc người dùng thật sự dùng mic.
    static func prewarmModel() async {
        if #available(iOS 26.0, *) {
            await ModernSpeechSession.prewarm()
        }
    }

    /// Dừng do NGƯỜI DÙNG (chạm mic) hoặc do màn hình biến mất — không phát kết quả.
    func stop() {
        hasDelivered = true
        teardown()
    }

    private func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            errorMessage = "Cần quyền nhận diện giọng nói. Bật lại trong Cài đặt iOS."
            return false
        }

        let micGranted = await Self.requestMicPermission()
        guard micGranted else {
            errorMessage = "Cần quyền micro để dùng giọng nói."
            return false
        }
        return true
    }

    /// `AVAudioApplication.requestRecordPermission` là iOS 17+ và là API được khuyến nghị;
    /// `AVAudioSession.requestRecordPermission` bị deprecated từ 17 nên chỉ dùng cho iOS 16.
    private static func requestMicPermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            }
        }
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    // MARK: - Engine mới (iOS 26+)

    @available(iOS 26.0, *)
    private func startModern() async throws {
        let session = try await ModernSpeechSession.make(
            onPartial: { [weak self] text in
                guard let self, !self.hasDelivered else { return }
                self.partialText = text
                // Chỉ hạ về mốc "lặng cuối câu" khi THẬT SỰ nghe được chữ. Engine hay gửi
                // partial RỖNG lúc mới khởi động — nhận nó là hạ mốc chờ từ 6s xuống 0.8s
                // ngay khi mic vừa mở, tức mất luôn thời gian chờ người dùng bắt đầu nói.
                if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    self.restartSilenceTimer(timeout: silenceInterval)
                }
            },
            onFinal: { [weak self] text in
                guard let self, !self.hasDelivered else { return }
                self.deliver(text.trimmingCharacters(in: .whitespaces).isEmpty ? [] : [text])
            },
            onFailure: { [weak self] in
                Task { @MainActor in await self?.finishWithPartial() }
            }
        )
        modernSession = session
        // Bắt `session` ra hằng local RỒI mới vào closure: closure của `installTap` chạy trên
        // audio thread (không phải MainActor), đọc `self.modernSession` trong đó là truy cập
        // state MainActor từ ngoài actor — lỗi biên dịch. `append` là `nonisolated` nên gọi được.
        try startAudioTap { buffer in
            session.append(buffer)
        }
    }

    // MARK: - Engine cũ (iOS 15-25)

    private func startLegacy() throws {
        guard let recognizer = SFSpeechRecognizer(locale: speechLocale), recognizer.isAvailable else {
            throw SpeechSetupError.localeNotSupported
        }
        legacyRecognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Tương đương `EXTRA_BIASING_STRINGS` bên Android.
        request.contextualStrings = amountBiasingStrings
        legacyRequest = request

        legacyTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                guard !self.hasDelivered else { return }
                if let result {
                    self.partialText = result.bestTranscription.formattedString
                    // Xem chú thích cùng chỗ trong `startModern`: partial rỗng KHÔNG được hạ
                    // mốc chờ xuống `silenceInterval`.
                    if !self.partialText.trimmingCharacters(in: .whitespaces).isEmpty {
                        self.restartSilenceTimer(timeout: silenceInterval)
                    }
                    if result.isFinal {
                        // Nhiều phương án giúp `SpeechAmountParser` chọn số tiền chính xác hơn.
                        var candidates = result.transcriptions.map(\.formattedString)
                        if candidates.isEmpty { candidates = [result.bestTranscription.formattedString] }
                        self.deliver(candidates.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                    }
                } else if error != nil {
                    await self.finishWithPartial()
                }
            }
        }

        // Bắt `request` ra hằng local, KHÔNG đọc `self.legacyRequest` trong closure — closure
        // chạy trên audio thread, đọc state MainActor ở đó là lỗi biên dịch.
        // `SFSpeechAudioBufferRecognitionRequest.append` an toàn gọi từ thread khác.
        try startAudioTap { buffer in
            request.append(buffer)
        }
    }

    // MARK: - Audio dùng chung

    /// Mở session + gắn tap lên micro. `onBuffer` chạy trên AUDIO THREAD, không phải MainActor —
    /// nơi gọi phải bắt sẵn thứ mình cần ra hằng local, tuyệt đối không đọc `self.<property>`
    /// bên trong closure.
    ///
    /// KHÔNG đánh dấu `@Sendable`: nhánh legacy cần bắt `SFSpeechAudioBufferRecognitionRequest`
    /// vào closure, mà class Objective-C đó chưa được Apple audit `Sendable` — thêm `@Sendable`
    /// sẽ sinh cảnh báo/lỗi ở chỗ đó dù việc gọi `append` từ thread khác là an toàn theo tài liệu.
    private func startAudioTap(_ onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            onBuffer(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    // MARK: - Chốt kết quả

    /// - Parameter timeout: `initialSpeechTimeout` cho lần hẹn ĐẦU (chờ người dùng bắt đầu
    ///   nói), `silenceInterval` cho các lần sau (đã nghe được chữ, đang đo khoảng lặng cuối
    ///   câu). Mặc định là mốc ngắn vì đa số lời gọi là từ callback nhận chữ.
    ///
    /// KHÔNG đặt `silenceInterval` làm giá trị mặc định của tham số: hằng cấp file cũng bị
    /// coi là main-actor-isolated, mà giá trị mặc định lại được đánh giá ở ngữ cảnh
    /// nonisolated — Swift báo lỗi. Hai nơi gọi tự truyền vào.
    private func restartSilenceTimer(timeout: TimeInterval) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            let service = self
            Task { @MainActor in await service?.finishWithPartial() }
        }
    }

    private func finishWithPartial() async {
        guard !hasDelivered else { return }
        let heard = partialText.trimmingCharacters(in: .whitespaces)
        deliver(heard.isEmpty ? [] : [heard])
    }

    private func deliver(_ candidates: [String]) {
        hasDelivered = true
        teardown()
        onResult?(candidates)
    }

    private func teardown() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        if #available(iOS 26.0, *), let session = modernSession as? ModernSpeechSession {
            session.finish()
        }
        modernSession = nil

        legacyRequest?.endAudio()
        legacyTask?.cancel()
        legacyRequest = nil
        legacyTask = nil
        legacyRecognizer = nil

        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func message(for error: Error) -> String {
        if let setupError = error as? SpeechSetupError {
            switch setupError {
            case .localeNotSupported:
                return "Máy chưa hỗ trợ nhận diện giọng nói tiếng Việt."
            case .conversionFailed:
                return "Không xử lý được âm thanh từ micro, vui lòng thử lại."
            }
        }
        return "Không mở được micro, vui lòng thử lại."
    }
}

private enum SpeechSetupError: Error {
    case localeNotSupported
    case conversionFailed
}

// MARK: - Engine mới, tách riêng để `@available` gọn

/// Bọc `SpeechAnalyzer` + `DictationTranscriber` (iOS 26+) — tách class riêng để phần
/// `SpeechRecognizerService` không phải rải `@available` khắp nơi.
/// `@unchecked Sendable`: `append` là `nonisolated` và chạy trên audio thread nên `self` phải
/// vượt biên actor được. An toàn vì mọi thứ `append` đọc đều là `let` (`analyzerFormat`,
/// `inputBuilder`, `converter`) và `converter` tự khoá state mutable của nó. `resultsTask` là
/// biến duy nhất mutable, chỉ được đụng tới từ MainActor (`make`/`finish`).
@available(iOS 26.0, *)
private final class ModernSpeechSession: @unchecked Sendable {
    private let analyzer: SpeechAnalyzer
    private let analyzerFormat: AVAudioFormat?
    private let inputBuilder: AsyncStream<AnalyzerInput>.Continuation
    private let converter = BufferConverter()
    private var resultsTask: Task<Void, Never>?

    private init(
        analyzer: SpeechAnalyzer,
        analyzerFormat: AVAudioFormat?,
        inputBuilder: AsyncStream<AnalyzerInput>.Continuation
    ) {
        self.analyzer = analyzer
        self.analyzerFormat = analyzerFormat
        self.inputBuilder = inputBuilder
    }

    /// Dựng phiên: đảm bảo model `vi-VN` đã tải, mở analyzer, bắt đầu đọc kết quả.
    static func make(
        onPartial: @escaping @MainActor (String) -> Void,
        onFinal: @escaping @MainActor (String) -> Void,
        onFailure: @escaping () -> Void
    ) async throws -> ModernSpeechSession {
        try await ensureModelReady()

        let transcriber = DictationTranscriber(locale: speechLocale, preset: .progressiveShortDictation)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        let (stream, builder) = AsyncStream<AnalyzerInput>.makeStream()
        try await analyzer.start(inputSequence: stream)

        let session = ModernSpeechSession(
            analyzer: analyzer, analyzerFormat: format, inputBuilder: builder
        )
        session.resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let isFinal = result.isFinal
                    await MainActor.run {
                        if isFinal { onFinal(text) } else { onPartial(text) }
                    }
                }
            } catch {
                // Stream lỗi/bị huỷ giữa chừng — chốt bằng phần đã nghe, không treo im lặng.
                onFailure()
            }
        }
        return session
    }

    /// Đẩy buffer micro vào analyzer. `nonisolated` vì được gọi từ AUDIO THREAD (closure của
    /// `installTap`), không phải MainActor. Chỉ đọc `let` property nên an toàn; `converter` tự
    /// bảo vệ state mutable bên trong bằng khoá riêng.
    nonisolated func append(_ buffer: AVAudioPCMBuffer) {
        guard let analyzerFormat,
              let converted = try? converter.convert(buffer, to: analyzerFormat) else { return }
        inputBuilder.yield(AnalyzerInput(buffer: converted))
    }

    /// Kết thúc phiên. Phải gọi `finalizeAndFinishThroughEndOfInput` (không chỉ đóng stream) để
    /// analyzer trả nốt kết quả cuối thay vì treo.
    func finish() {
        inputBuilder.finish()
        let analyzer = self.analyzer
        Task { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
        resultsTask?.cancel()
        resultsTask = nil
    }

    /// Tải trước model, bỏ qua kết quả — dùng cho `SpeechRecognizerService.prewarmModel()`.
    /// Không throw: thất bại thì để `start()` báo lỗi lúc người dùng thật sự bấm mic.
    static func prewarm() async {
        try? await ensureModelReady()
    }

    /// Kiểm tra `vi-VN` được hỗ trợ + đã cài on-device chưa, tải nếu thiếu. Cache bằng `Task`
    /// tĩnh: nhiều màn gọi `start()` chỉ tải model đúng một lần.
    private static var modelReady: Task<Bool, Never>?

    private static func ensureModelReady() async throws {
        if let existing = modelReady {
            guard await existing.value else { throw SpeechSetupError.localeNotSupported }
            return
        }
        let task = Task<Bool, Never> {
            do {
                try await downloadModelIfNeeded()
                return true
            } catch {
                return false
            }
        }
        modelReady = task
        guard await task.value else { throw SpeechSetupError.localeNotSupported }
    }

    private static func downloadModelIfNeeded() async throws {
        let target = speechLocale.identifier(.bcp47)

        let supported = await DictationTranscriber.supportedLocales
        guard supported.map({ $0.identifier(.bcp47) }).contains(target) else {
            throw SpeechSetupError.localeNotSupported
        }

        let installed = await DictationTranscriber.installedLocales
        guard !installed.map({ $0.identifier(.bcp47) }).contains(target) else { return }

        // Locale được hỗ trợ nhưng chưa tải model xuống máy — xin AssetInventory tải về. Lần đầu
        // có thể mất vài giây tới vài chục giây tuỳ mạng; các lượt sau rơi vào `installed` ở trên.
        let transcriber = DictationTranscriber(locale: speechLocale, preset: .progressiveShortDictation)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }
}

/// Chuyển `AVAudioPCMBuffer` từ format của input node (hardware, thường 48kHz) sang format mà
/// `SpeechAnalyzer` yêu cầu. BẮT BUỘC phải có — feed thẳng buffer sai format khiến analyzer chạy
/// nhưng không bao giờ trả kết quả, không có lỗi nào để biết vì sao.
///
/// `nonisolated` + `@unchecked Sendable`: được gọi từ audio thread (qua
/// `ModernSpeechSession.append`), không phải MainActor. `AVAudioConverter` được cache lại giữa
/// các frame nên là state mutable — bảo vệ bằng `NSLock` thay vì dựa vào actor.
private final class BufferConverter: @unchecked Sendable {
    private let lock = NSLock()
    private var converter: AVAudioConverter?

    nonisolated func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        if buffer.format == format { return buffer }

        lock.lock()
        defer { lock.unlock() }

        let converter: AVAudioConverter
        if let existing = self.converter,
           existing.outputFormat == format, existing.inputFormat == buffer.format {
            converter = existing
        } else {
            guard let created = AVAudioConverter(from: buffer.format, to: format) else {
                throw SpeechSetupError.conversionFailed
            }
            converter = created
            self.converter = converter
        }

        let sampleRateRatio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let scaledInputFrameLength = Double(buffer.frameLength) * sampleRateRatio
        let frameCapacity = AVAudioFrameCount(scaledInputFrameLength.rounded(.up))
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            throw SpeechSetupError.conversionFailed
        }

        var error: NSError?
        var hasFedInput = false
        converter.convert(to: outputBuffer, error: &error) { _, inputStatus in
            if hasFedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            hasFedInput = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if let error { throw error }
        return outputBuffer
    }
}
