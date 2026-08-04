//
//  QrScanView.swift
//  nano ewallet
//
//  Mirror QrScanScreen.kt — camera quét mã QR VietQR (EMVCo). Chỉ target ngân hàng:
//  quét xong gửi rawValue lên BE `banks/parse-qr` (verify CRC + tra tên chủ TK),
//  rồi vào thẳng BankTransferView với draft đã điền sẵn (thẻ người nhận khoá) —
//  dùng chung màn chuyển khoản ngân hàng nhập tay, không có màn "QR_PAYMENT" riêng.
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
    /// "Cấp cứu ví tui" — mở danh bạ ví ở chế độ xin tiền.
    var onEmergency: () -> Void = {}
    /// OneTouch nhận ra nội dung dán là VÍ nội bộ -> sang màn chuyển ví.
    var onWalletRecipient: (WalletTransferDraft) -> Void = { _ in }

    @StateObject private var scanner = QrScannerController()

    @State private var isParsing = false
    @State private var errorMessage: String?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var lastHandledValue: String?
    @State private var isDecodingImage = false
    /// Thanh quét đang ở nửa dưới khung — lật một lần lúc hiện màn để khởi động vòng lặp.
    @State private var isScanLineDown = false

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    /// Người dùng bật "Giảm chuyển động" thì bỏ hẳn thanh trượt.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Số đo lấy nguyên từ QrScanScreen.kt.
    private static let frameSize: CGFloat = 310
    private static let frameShiftUp: CGFloat = 25
    private static let cornerLength: CGFloat = 34
    private static let cornerThickness: CGFloat = 4

    var body: some View {
        ZStack {
            if scanner.isPermissionDenied {
                permissionPrompt
            } else {
                CameraPreviewView(session: scanner.session)
                    .ignoresSafeArea()
            }

            scrimOverlay
            viewfinder
            doubleTapToHomeLayer

            VStack {
                header
                Spacer()
                if let errorMessage {
                    Text(errorMessage)
                        .font(AppFont.beVietnamPro(13))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }
                bottomBar
            }

            // Chặn mọi thao tác tới khi backend trả kết quả — bấm tiếp lúc này chỉ tạo
            // thêm lượt parse trùng.
            if isParsing {
                ZStack {
                    Color.black.opacity(0.65).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView().tint(AppColor.brand).scaleEffect(1.2)
                        Text("Đang xử lý...")
                            .font(AppFont.beVietnamPro(14, .medium))
                            .foregroundStyle(.white)
                    }
                }
                .transition(.opacity)
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

    /// Nút tròn trong header — nền trong suốt, chỉ icon (mirror `HeaderCircleButton`).
    private var header: some View {
        ZStack {
            Text("Quét mã QR")
                .font(AppFont.beVietnamPro(18, .bold))
                .foregroundStyle(.white)

            HStack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    scanner.toggleTorch()
                } label: {
                    Image(systemName: scanner.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: 20))
                        // Đèn bật -> đổi màu brand để thấy rõ trạng thái.
                        .foregroundStyle(scanner.isTorchOn ? AppColor.brand : .white)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var permissionPrompt: some View {
        Button {
            scanner.openSystemSettings()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "camera")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
                Text("Chạm để bật camera")
                    .font(AppFont.beVietnamPro(14, .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .ignoresSafeArea()
    }

    // MARK: - Khung quét

    /// Tâm khung: giữa màn hình, đẩy lên `frameShiftUp`.
    private func frameCenter(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2 - Self.frameShiftUp)
    }

    /// Lớp tối phủ ngoài khung, KHOÉT LỖ VUÔNG ở giữa để vùng quét sáng rõ.
    /// Chạm hai lần vào vùng camera là về Home — phím tắt cho người dùng quen tay, nút
    /// mũi tên góc trên trái vẫn là đường chính.
    ///
    /// Nằm TRƯỚC lớp header/dải nút trong `ZStack` nên hai lớp đó vẽ đè lên và nhận chạm
    /// trước — không tranh cử chỉ với nút nào.
    ///
    /// Tắt khi VoiceOver đang bật: với trình đọc màn hình, chạm hai lần là cách kích hoạt
    /// phần tử đang chọn, gán thêm nghĩa "về Home" lên đó sẽ gây nhầm.
    @ViewBuilder
    private var doubleTapToHomeLayer: some View {
        if !voiceOverEnabled {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2, perform: onBack)
        }
    }

    private var scrimOverlay: some View {
        GeometryReader { geo in
            let center = frameCenter(in: geo.size)
            Rectangle()
                .fill(Color.black.opacity(0.6))
                .mask {
                    Rectangle()
                        .overlay {
                            // Vuông, KHÔNG bo góc — phải trùng khít với 4 góc chữ L.
                            Rectangle()
                                .frame(width: Self.frameSize, height: Self.frameSize)
                                .position(center)
                                .blendMode(.destinationOut)
                        }
                }
        }
        .allowsHitTesting(false)
    }

    /// Khung 4 góc chữ L + logo + hướng dẫn + hàng logo cổng thanh toán.
    private var viewfinder: some View {
        GeometryReader { geo in
            let center = frameCenter(in: geo.size)
            let half = Self.frameSize / 2

            ZStack {
                ForEach(FrameCorner.allCases, id: \.self) { corner in
                    cornerMark(corner)
                }
                .frame(width: Self.frameSize, height: Self.frameSize)
                .position(center)

                if !reduceMotion {
                    scanLine
                        .frame(width: Self.frameSize, height: Self.frameSize)
                        .position(center)
                }

                Image("logo_white")
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white)
                    .frame(height: 44)
                    .position(x: center.x, y: center.y - half - 70)

                Text("Hướng camera vào mã QR cần quét")
                    .font(AppFont.beVietnamPro(13))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .position(x: center.x, y: center.y - half - 28)

                gatewayLogos
                    .position(x: center.x, y: center.y + half + 44)
            }
        }
        .allowsHitTesting(false)
    }

    /// Thanh ngang trượt lên xuống trong khung ngắm — dấu hiệu "đang quét" cho người dùng
    /// biết camera còn sống, vì màn này không có gì khác động đậy.
    ///
    /// Dừng khi đang xử lý kết quả: lúc đó camera đã ngừng nhận, để thanh chạy tiếp là báo
    /// sai rằng vẫn đang quét.
    private var scanLine: some View {
        // Chừa 8 điểm mỗi đầu để thanh không đè lên nét góc chữ L.
        let travel = Self.frameSize - 16
        return LinearGradient(
            colors: [
                AppColor.brand.opacity(0),
                AppColor.brand.opacity(0.9),
                AppColor.brand.opacity(0),
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 2)
        .shadow(color: AppColor.brand.opacity(0.8), radius: 6)
        .offset(y: isScanLineDown ? travel / 2 : -travel / 2)
        .animation(
            .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
            value: isScanLineDown
        )
        .opacity(isParsing || isDecodingImage ? 0 : 1)
        .onAppear { isScanLineDown = true }
    }

    /// Cổng thanh toán hỗ trợ — logo tô trắng, ngăn nhau bằng vạch dọc mờ.
    private var gatewayLogos: some View {
        HStack(spacing: 12) {
            gatewayLogo("ic_pay_vietqr")
            gatewayDivider
            gatewayLogo("ic_pay_vnpay")
            gatewayDivider
            gatewayLogo("ic_pay_payos")
        }
    }

    private func gatewayLogo(_ name: String) -> some View {
        Image(name)
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(.white)
            .frame(height: 14)
    }

    private var gatewayDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.25))
            .frame(width: 1, height: 14)
    }

    private enum FrameCorner: CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        var isTop: Bool { self == .topLeading || self == .topTrailing }
        var isLeading: Bool { self == .topLeading || self == .bottomLeading }

        var alignment: Alignment {
            switch self {
            case .topLeading: return .topLeading
            case .topTrailing: return .topTrailing
            case .bottomLeading: return .bottomLeading
            case .bottomTrailing: return .bottomTrailing
            }
        }
    }

    /// Một góc chữ L: nhánh ngang + nhánh dọc, màu brand.
    private func cornerMark(_ corner: FrameCorner) -> some View {
        ZStack(alignment: corner.isTop ? .top : .bottom) {
            Rectangle()
                .fill(AppColor.brand)
                .frame(width: Self.cornerLength, height: Self.cornerThickness)

            HStack(spacing: 0) {
                if !corner.isLeading { Spacer(minLength: 0) }
                Rectangle()
                    .fill(AppColor.brand)
                    .frame(width: Self.cornerThickness, height: Self.cornerLength)
                if corner.isLeading { Spacer(minLength: 0) }
            }
        }
        .frame(width: Self.cornerLength, height: Self.cornerLength)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
    }

    // MARK: - Thanh dưới

    /// Pill 4 phân đoạn dùng CHUNG một khối kính mờ, ngăn nhau bằng vạch dọc —
    /// mirror khối cuối QrScanScreen.kt.
    private var bottomBar: some View {
        HStack(spacing: 0) {
            pillSegment(title: "OneTouch", isNew: true) {
                Task { await handleOneTouch() }
            } icon: {
                TransactionIcon(kind: .pasteCk, tint: .white)
                    .frame(width: 22, height: 22)
            }

            pillDivider

            pillSegment(title: "Cấp cứu ví tui", isNew: true, action: onEmergency) {
                TransactionIcon(kind: .requestMoney, tint: .white)
                    .frame(width: 22, height: 22)
            }

            pillDivider

            // PhotosPicker tự là nút nên không bọc thêm Button. Label closure của nó
            // KHÔNG kế thừa `@MainActor`, nên phải dựng sẵn view ở đây (context
            // @MainActor) rồi truyền vào — gọi `pillLabel`/đọc `isDecodingImage` trực
            // tiếp trong closure sẽ thành lỗi ở Swift 6.
            let photoLabel = pillLabel(title: "Tải từ ảnh", isNew: false) { photoPickerIcon }
            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                photoLabel
            }
            .disabled(isDecodingImage)

            pillDivider

            pillSegment(title: "Mã nhận tiền", isNew: false, action: onReceiveQr) {
                Image(systemName: "qrcode")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
            }
        }
        .frame(height: 74)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 26)
    }

    private func pillSegment<Icon: View>(
        title: String,
        isNew: Bool,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button(action: action) {
            pillLabel(title: title, isNew: isNew, icon: icon)
        }
        .buttonStyle(.plain)
    }

    /// Icon ô "Tải từ ảnh" — vòng xoay khi đang decode, ngược lại là icon ảnh.
    @ViewBuilder
    private var photoPickerIcon: some View {
        if isDecodingImage {
            ProgressView()
                .tint(.white)
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: "photo")
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
        }
    }

    private func pillLabel<Icon: View>(
        title: String,
        isNew: Bool,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        VStack(spacing: 6) {
            ZStack {
                icon()
                if isNew {
                    Text("MỚI")
                        .font(AppFont.beVietnamPro(8, .bold))
                        .foregroundStyle(.white)
                        // fixedSize: badge nằm trong ZStack rộng 22pt nên bị ép xuống
                        // dòng thành "MỚ / I" nếu không cho nó giữ bề rộng tự nhiên.
                        .fixedSize()
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(hex: 0xFF3B30), in: RoundedRectangle(cornerRadius: 6))
                        .offset(x: 13, y: -9)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(width: 22, height: 22)

            Text(title)
                .font(AppFont.beVietnamPro(11, .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    private var pillDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.4))
            .frame(width: 1, height: 30)
    }

    // MARK: - Xử lý QR

    // MARK: - OneTouch

    /// Một chạm: đọc bộ nhớ tạm rồi tự nhận diện QR / tin nhắn CK / số ví.
    private func handleOneTouch() async {
        guard !isParsing else { return }
        errorMessage = nil
        isParsing = true
        defer { isParsing = false }
        route(await OneTouchResolver.resolveClipboard())
    }

    /// Đưa kết quả nhận diện tới đúng màn.
    private func route(_ result: OneTouchResult) {
        switch result {
        case .bank(let draft):
            onParsed(draft)
        case .wallet(let draft):
            onWalletRecipient(draft)
        case .failure(let message):
            errorMessage = message
            // Cho phép quét lại mã vừa thất bại.
            lastHandledValue = nil
        }
    }

    private func handleQrDetected(_ rawValue: String) {
        guard !isParsing else { return }
        errorMessage = nil
        isParsing = true
        Task {
            defer { isParsing = false }
            route(await OneTouchResolver.resolveQr(rawValue))
        }
    }

    /// "Tải từ ảnh": ảnh chọn từ thư viện. Đi qua cùng resolver với OneTouch nên ảnh
    /// KHÔNG có mã QR vẫn dùng được — OCR rồi bóc như tin nhắn, thay vì báo lỗi.
    private func handlePickedPhoto(_ item: PhotosPickerItem) async {
        photoPickerItem = nil
        isDecodingImage = true
        errorMessage = nil
        defer { isDecodingImage = false }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            errorMessage = "Không đọc được ảnh"
            return
        }
        isParsing = true
        defer { isParsing = false }
        route(await OneTouchResolver.resolve(image: image))
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
    /// User đã từ chối quyền camera — hiện màn "Chạm để bật camera" thay cho preview.
    @Published private(set) var isPermissionDenied = false

    private var device: AVCaptureDevice?
    private var isConfigured = false

    func requestPermissionAndStart() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isPermissionDenied = false
            startSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            isPermissionDenied = !granted
            if granted { startSession() }
        default:
            // Từ chối rồi thì app KHÔNG xin lại được, phải qua Cài đặt iOS.
            isPermissionDenied = true
        }
    }

    /// Mở Cài đặt iOS để bật lại quyền camera.
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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
