//
//  QrScanView.swift
//  nano ewallet
//
//  Mirror QrScanScreen.kt — camera quét mã QR VietQR (EMVCo). Chỉ target ngân hàng:
//  quét xong gửi rawValue lên BE `banks/parse-qr` (verify CRC + tra tên chủ TK),
//  rồi vào thẳng BankTransferAmountView với draft đã điền sẵn — dùng chung màn
//  chuyển khoản ngân hàng nhập tay, không có màn "QR_PAYMENT" riêng.
//
//  Dùng AVFoundation (AVCaptureMetadataOutput) thay ML Kit bên Android — cùng
//  hiệu quả cho QR code, là API chuẩn của iOS nên không cần thư viện ngoài.
//

import SwiftUI
import Combine
import AVFoundation
import PhotosUI

@MainActor
struct QrScanView: View {
    let onBack: () -> Void
    let onParsed: (BankTransferDraft) -> Void
    let onReceiveQr: () -> Void

    @StateObject private var scanner = QrScannerController()

    @State private var isParsing = false
    @State private var errorMessage: String?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var lastHandledValue: String?

    var body: some View {
        ZStack {
            CameraPreviewView(session: scanner.session)
                .ignoresSafeArea()

            scrimOverlay

            VStack {
                header
                Spacer()
                if let errorMessage {
                    Text(errorMessage)
                        .font(AppFont.beVietnamPro(13))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.bottom, 12)
                }
                bottomBar
            }

            if isParsing {
                Color.black.opacity(0.4).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text("Đang xử lý...")
                        .font(AppFont.beVietnamPro(14))
                        .foregroundStyle(.white)
                }
            }
        }
        .background(Color.black)
        .task {
            await scanner.requestPermissionAndStart()
        }
        .onDisappear { scanner.stop() }
        .onChange(of: scanner.lastScannedValue) { _, newValue in
            guard let newValue, newValue != lastHandledValue else { return }
            lastHandledValue = newValue
            handleQrDetected(newValue)
        }
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            Task { await handlePickedPhoto(item) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("QUÉT MÃ QR")
                .font(AppFont.beVietnamPro(15, .bold))
                .foregroundStyle(.white)
                .tracking(2)

            Spacer()

            Button {
                scanner.toggleTorch()
            } label: {
                Image(systemName: scanner.isTorchOn ? "bolt.fill" : "bolt.slash")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Khung quét

    private static let frameSize: CGFloat = 260

    private var scrimOverlay: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2 - 40)
            let frame = Self.frameSize

            ZStack {
                Rectangle().fill(Color.black.opacity(0.55))
                    .mask {
                        Rectangle()
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .frame(width: frame, height: frame)
                                    .position(center)
                                    .blendMode(.destinationOut)
                            }
                    }

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                    .frame(width: frame, height: frame)
                    .position(center)

                Text("Đưa mã QR vào khung để quét")
                    .font(AppFont.beVietnamPro(13, .medium))
                    .foregroundStyle(.white)
                    .position(x: center.x, y: center.y - frame / 2 - 24)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Thanh dưới

    private var bottomBar: some View {
        HStack(spacing: 0) {
            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                bottomItem(icon: "photo.on.rectangle", title: "Tải từ ảnh")
            }

            Button(action: onReceiveQr) {
                bottomItem(icon: "qrcode", title: "Mã nhận tiền")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private nonisolated func bottomItem(icon: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.white)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Xử lý QR

    private func handleQrDetected(_ rawValue: String) {
        guard !isParsing else { return }
        errorMessage = nil
        isParsing = true
        Task {
            defer { isParsing = false }
            do {
                let parsed = try await BankService.parseQr(rawQrData: rawValue)
                onParsed(
                    BankTransferDraft(
                        bin: parsed.bankBin, bankName: parsed.bankName ?? "Ngân hàng",
                        accNo: parsed.accountNumber, accType: 0, holderName: parsed.accountName,
                        prefillAmount: parsed.amount, prefillContent: parsed.content,
                        amountEditable: parsed.isAmountEditable, contentEditable: parsed.isContentEditable
                    )
                )
            } catch let error as APIError {
                errorMessage = error.message
                lastHandledValue = nil
            } catch {
                errorMessage = "Không đọc được mã QR, vui lòng thử lại"
                lastHandledValue = nil
            }
        }
    }

    private func handlePickedPhoto(_ item: PhotosPickerItem) async {
        photoPickerItem = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let ciImage = CIImage(image: image) else {
            errorMessage = "Không đọc được ảnh"
            return
        }
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode, context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        guard let features = detector?.features(in: ciImage) as? [CIQRCodeFeature],
              let rawValue = features.first?.messageString else {
            errorMessage = "Không tìm thấy mã QR trong ảnh"
            return
        }
        handleQrDetected(rawValue)
    }
}

// MARK: - Camera controller

/// Quản lý `AVCaptureSession` + phát hiện QR qua `AVCaptureMetadataOutput` — thay ML Kit
/// bên Android bằng API chuẩn iOS.
@MainActor
final class QrScannerController: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    let session = AVCaptureSession()

    @Published private(set) var lastScannedValue: String?
    @Published private(set) var isTorchOn = false

    private var device: AVCaptureDevice?
    private var isConfigured = false

    func requestPermissionAndStart() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { startSession() }
        default:
            break // đã từ chối — UI có thể thêm trạng thái riêng nếu cần sau này
        }
    }

    private func startSession() {
        guard !isConfigured else {
            Task.detached { [session] in session.startRunning() }
            return
        }
        isConfigured = true

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        self.device = device

        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
        }
        session.commitConfiguration()

        Task.detached { [session] in session.startRunning() }
    }

    func stop() {
        Task.detached { [session] in session.stopRunning() }
    }

    func toggleTorch() {
        guard let device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = isTorchOn ? .off : .on
            isTorchOn.toggle()
            device.unlockForConfiguration()
        } catch {
            // torch không khả dụng — bỏ qua, không phải lỗi nghiêm trọng
        }
    }

    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr, let value = object.stringValue else { return }
        Task { @MainActor in self.lastScannedValue = value }
    }
}

/// Bọc `AVCaptureVideoPreviewLayer` cho SwiftUI.
private struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

#Preview {
    QrScanView(onBack: {}, onParsed: { _ in }, onReceiveQr: {})
}
