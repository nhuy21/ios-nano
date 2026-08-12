//
//  QrScanView.swift
//  nano ewallet
//
//  Mirror QrScanScreen.kt — camera quét mã QR VietQR (EMVCo). Chỉ target ngân hàng:
//  quét xong gửi rawValue lên BE `banks/parse-qr` (verify CRC + tra tên chủ TK),
//  rồi vào thẳng BankTransferView với draft đã điền sẵn (thẻ người nhận khoá) —
//  dùng chung màn chuyển khoản ngân hàng nhập tay, không có màn "QR_PAYMENT" riêng.
//
//  Quét QR bằng AVFoundation (capture) + Vision (`VNDetectBarcodesRequest`) để decode — KHÔNG
//  dùng `AVCaptureMetadataOutput` (bộ giải mã hardware built-in của Apple): thực tế fail rất
//  nhiều với mã mờ/xa/thiếu sáng/nghiêng góc. Vision dùng computer vision để decode, cùng kiến
//  trúc với ML Kit (BarcodeScanning) bên Android — cả hai đều xử lý CVPixelBuffer/frame ảnh
//  bằng mô hình học máy thay vì đọc trực tiếp bằng hardware camera.
//

import SwiftUI
import Combine
import AVFoundation
import Vision
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
    /// Màn quét có đang ở trên cùng ngăn xếp không. `false` khi đã đẩy sang màn chuyển
    /// tiền — quay lại `true` thì phải mở lại việc quét, xem `.onChangeCompat` bên dưới.
    var isActive: Bool = true

    @StateObject private var scanner = QrScannerController()

    /// Đang bóc tách nội dung do người dùng CHỦ ĐỘNG đưa vào (dán bộ nhớ tạm, chọn ảnh) —
    /// có lớp phủ chặn màn vì họ vừa bấm nút và cần biết app đang chờ.
    @State private var isParsing = false
    /// Đang bóc mã camera vừa bắt được — KHÔNG hiện lớp phủ, xem `handleQrDetected`.
    @State private var isScanningQr = false
    @State private var errorMessage: String?
    /// Ảnh chọn từ thư viện có nhiều người nhận -> hỏi chọn, không đoán hộ.
    @State private var choiceList: OneTouchChoiceList?
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
        // Nền đen là lớp bịt phần camera preview không phủ tới: preview tràn viền bằng
        // `.ignoresSafeArea()` riêng nhưng theo tỉ lệ 4:3/16:9 nên không kín mọi kích thước
        // máy. Dùng `screenBackground` (ép giãn hết khung TRƯỚC khi tô) thay vì tự
        // `.background(...ignoresSafeArea())` — thiếu bước ép giãn thì nền không có gì để
        // tràn ra, vẫn hở hai dải sáng ở status bar / home indicator.
        .screenBackground(Color.black, alignment: .center)
        .instantOverlayCover(item: $choiceList) { pick in
            ActionChooserSheet(
                title: pick.title,
                subtitle: "Chọn tài khoản bạn muốn chuyển tới",
                actions: pick.options.map { choice in
                    .init(
                        systemImage: choice.systemImage,
                        title: choice.holderName,
                        subtitle: choice.subtitle,
                        handler: {
                            switch choice {
                            case .bank(let draft): onParsed(draft)
                            case .wallet(let draft): onWalletRecipient(draft)
                            }
                        }
                    )
                },
                onDismiss: {
                    choiceList = nil
                    // Mở lại việc quét: bỏ qua hộp chọn mà không reset thì camera vẫn coi
                    // như đã xong việc và không xử lý frame nào nữa. Phải reset CẢ hai —
                    // state ở view lẫn cờ bên trong controller.
                    lastHandledValue = nil
                    scanner.resumeScanning()
                }
            )
        }
        .task {
            await scanner.requestPermissionAndStart()
        }
        .onDisappear { scanner.stop() }
        // Quay lại từ màn chuyển tiền: mở lại việc quét. Không có nhánh này thì quét thành
        // công MỘT lần là màn quét chết — cờ "đã tìm thấy" và `lastHandledValue` giữ nguyên
        // nên mọi frame sau đều bị bỏ qua, mà camera vẫn chiếu hình nên nhìn không ra.
        //
        // Dựa vào ngăn xếp (`isActive`) chứ không dùng `onAppear`: màn quét là gốc của
        // `NavigationStack`, đẩy màn khác lên không chắc chắn bắn `onDisappear`/`onAppear`.
        .onChangeCompat(of: isActive) { _, active in
            guard active else { return }
            lastHandledValue = nil
            errorMessage = nil
            scanner.resumeScanning()
        }
        .onChangeCompat(of: scanner.lastScannedValue) { _, newValue in
            guard let newValue, newValue != lastHandledValue else { return }
            lastHandledValue = newValue
            handleQrDetected(newValue)
        }
        .onChangeNewCompat(of: photoPickerItem) { item in
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
                .buttonStyle(PressableButtonStyle())

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
                .buttonStyle(PressableButtonStyle())
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
        // Không nhún: đây là lớp phủ kín màn, co lại sẽ hở viền đen quanh mép.
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
        // Phủ CẢ vùng status bar và home indicator: `GeometryReader` chỉ chiếm vùng an toàn
        // nên lớp sẫm dừng đúng ở hai mép đó, để hở hai dải camera sáng nguyên ở trên/dưới —
        // nhìn như lớp phủ bị cắt dở.
        .ignoresSafeArea()
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

                // Hai cử chỉ thoát màn đều KHÔNG có dấu hiệu nào trên UI (nút back nằm tít
                // trên cùng), không nói ra thì gần như không ai tự phát hiện.
                // Mờ hơn dòng hướng dẫn quét ở trên vì đây chỉ là mẹo phụ, không phải việc
                // chính người dùng đang làm.
                //
                // Bật VoiceOver thì chạm hai lần là cử chỉ KÍCH HOẠT của hệ thống nên lớp
                // `doubleTapToHomeLayer` tự tắt — chỉ còn kéo xuống, nhắc y nguyên là sai.
                Text(
                    voiceOverEnabled
                        ? "Kéo xuống để về Trang chủ"
                        : "Chạm hai lần hoặc kéo xuống để về Trang chủ"
                )
                .font(AppFont.beVietnamPro(12))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .position(x: center.x, y: center.y + half + 84)
            }
        }
        // PHẢI khớp `.ignoresSafeArea()` của `scrimOverlay`: hai lớp cùng tính tâm khung qua
        // `frameCenter(in: geo.size)`, lệch hệ toạ độ là lỗ cắt trên lớp sẫm không trùng với
        // 4 góc chữ L vẽ ở đây.
        .ignoresSafeArea()
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
        .buttonStyle(PressableButtonStyle())
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
        case .choose(let title, let options):
            choiceList = OneTouchChoiceList(title: title, options: options)
        case .failure(let message):
            errorMessage = message
            // Cho phép quét lại mã vừa thất bại — cả state ở view (lastHandledValue) lẫn cờ
            // "đã tìm thấy" bên trong controller (didFindCode) đều phải reset, thiếu 1 trong 2
            // là camera coi như đã xong việc và không xử lý frame nào nữa.
            lastHandledValue = nil
            scanner.resumeScanning()
        }
    }

    private func handleQrDetected(_ rawValue: String) {
        guard !isParsing, !isScanningQr else { return }
        errorMessage = nil
        // Cờ RIÊNG, không dùng `isParsing`: camera bắt mã liên tục nên mã mờ/không hợp lệ sẽ
        // làm lớp phủ đen bật-tắt dồn dập, nhìn như màn hình nháy. Quét là hành động tự động
        // — lỗi thì chỉ cần báo rồi cho quét lại, không cần chặn màn.
        isScanningQr = true
        Task {
            defer { isScanningQr = false }
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

/// Quản lý `AVCaptureSession` + phát hiện QR qua `Vision` (`VNDetectBarcodesRequest`).
///
/// KHÔNG dùng `AVCaptureMetadataOutput` (bộ giải mã hardware/firmware built-in của Apple):
/// thực tế đo được nó fail rất nhiều với mã mờ/xa/thiếu sáng/nghiêng góc so với ML Kit bên
/// Android — ML Kit dùng computer vision (mô hình học máy) để decode, khoan dung hơn hẳn so với
/// bộ đọc barcode hardware truyền thống. `Vision` là framework CV/ML tương đương của Apple, xử
/// lý từng frame `CVPixelBuffer` giống hệt cách Android lấy frame qua `ImageAnalysis` rồi đưa
/// vào `BarcodeScanning.getClient()` — cùng kiến trúc, không chỉ cùng "hiệu quả".
@MainActor
final class QrScannerController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()

    @Published private(set) var lastScannedValue: String?
    @Published private(set) var isTorchOn = false
    /// User đã từ chối quyền camera — hiện màn "Chạm để bật camera" thay cho preview.
    @Published private(set) var isPermissionDenied = false

    private var device: AVCaptureDevice?
    private var isConfigured = false

    /// Toàn bộ state đọc/ghi từ `captureOutput` (chạy trên `processingQueue`, `nonisolated`)
    /// PHẢI nằm sau khoá riêng, không dựa vào MainActor: class này là `@MainActor` (mặc định
    /// project), nhưng `captureOutput` là `nonisolated` nên tuyệt đối không truy cập trực tiếp
    /// property MainActor-isolated được — và dù có nhảy qua MainActor được thì mỗi frame phải
    /// đổi thread sẽ triệt tiêu lợi ích throttle. `NSLock` giữ mọi thứ trên đúng 1 hàng đợi.
    private final class ScanState: @unchecked Sendable {
        private let lock = NSLock()
        /// Throttle: Vision tốn CPU/Neural Engine hơn nhiều so với decode hardware, không thể
        /// chạy ở tốc độ 30-60fps của camera. Mirror `STRATEGY_KEEP_ONLY_LATEST` bên Android
        /// (CameraX) — cờ này bỏ qua frame mới nếu frame trước chưa xử lý xong.
        private var isProcessingFrame = false
        /// Đã tìm thấy mã hợp lệ — dừng xử lý frame tiếp, tránh Vision chạy tiếp trong lúc UI
        /// đã chuyển màn (view còn sống thêm vài chục ms sau khi state đổi).
        private var didFindCode = false

        /// `true` = đã có frame khác đang xử lý hoặc đã tìm thấy mã, gọi nơi khác bỏ qua ngay.
        /// Nếu được phép chạy thì tự chiếm `isProcessingFrame` LUÔN trong cùng 1 lần khoá —
        /// tách "kiểm tra" và "chiếm" thành 2 bước sẽ hở race giữa 2 lần gọi liên tiếp.
        func tryBeginProcessing() -> Bool {
            lock.withLock {
                guard !isProcessingFrame, !didFindCode else { return false }
                isProcessingFrame = true
                return true
            }
        }

        func endProcessing() {
            lock.withLock { isProcessingFrame = false }
        }

        func markFound() {
            lock.withLock { didFindCode = true }
        }

        func reset() {
            lock.withLock { didFindCode = false }
        }
    }

    private let scanState = ScanState()
    private let processingQueue = DispatchQueue(label: "dev.casso.nanowallet.qrscan", qos: .userInitiated)

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
        configureFocus(device)

        session.beginConfiguration()
        // .high (không phải preset mặc định): độ phân giải đủ để đọc mã QR nhỏ/xa mà không kéo
        // tụt tốc độ xử lý mỗi frame — mirror setTargetResolution(1280, 720) bên Android.
        if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureVideoDataOutput()
        // BGRA: định dạng Vision đọc trực tiếp không cần convert, tránh tốn CPU đổi màu mỗi
        // frame khi ta đã phải throttle vì Vision vốn đã chậm hơn hardware decode.
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        // true: mirror STRATEGY_KEEP_ONLY_LATEST — frame mới đè frame cũ chưa kịp lấy, không
        // xếp hàng đợi làm trễ dần nếu Vision xử lý chậm hơn tốc độ camera.
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setSampleBufferDelegate(self, queue: processingQueue)
        }
        session.commitConfiguration()

        Task.detached { [session] in session.startRunning() }
    }

    /// Cấu hình lấy nét cho quét QR cự ly gần — mặc định của `AVCaptureDevice` được tối ưu cho
    /// chụp ảnh (autofocus mượt, ưu tiên vùng xa), không phải cho việc phải lấy nét NHANH và
    /// GẦN liên tục.
    private func configureFocus(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            // Mã QR luôn ở cự ly gần (người dùng đưa camera sát mã) — giới hạn near loại bỏ
            // hẳn khả năng camera "phân vân" lấy nét ở khoảng xa.
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            // Tắt smooth focus: chế độ này cố tình làm chuyển tiêu cự CHẬM/mượt cho quay video,
            // ngược hoàn toàn với nhu cầu ở đây là bắt nét NHANH mỗi khi mã QR xuất hiện.
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = false
            }
            device.unlockForConfiguration()
        } catch {
            // Không khoá được config thì vẫn dùng camera với mặc định — quét chậm hơn, không
            // phải lỗi nghiêm trọng khiến màn không dùng được.
        }
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

    /// Chạy trên `processingQueue`, KHÔNG phải main — mirror executor riêng của
    /// `imageAnalysis.setAnalyzer` bên Android, để Vision không chặn UI thread.
    ///
    /// `nonisolated` bắt buộc vì đây là yêu cầu của protocol delegate không phải `async` — mọi
    /// state dùng trong hàm này đi qua `scanState` (khoá riêng), KHÔNG đụng property nào của
    /// `@MainActor` class này.
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard scanState.tryBeginProcessing(),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        defer { scanState.endProcessing() }

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        // KHÔNG giới hạn `regionOfInterest`: quét TOÀN khung ảnh, giống ML Kit bên Android
        // (analyzer nhận nguyên `InputImage`, không cắt vùng nào).
        //
        // Bản trước cắt theo khung ngắm và đó là lý do gần như không quét được. `regionOfInterest`
        // của Vision tính trên ảnh ĐÃ XOAY theo `orientation`, còn giá trị lấy từ
        // `metadataOutputRectConverted` lại nằm trong hệ toạ độ của bộ đệm GỐC (camera nằm
        // ngang). Giữa hai hệ đó lệch nhau một phép xoay 90° chứ không chỉ lật trục Y — lật Y
        // như cũ làm vùng quét rơi vào một góc khác hẳn nơi người dùng đang ngắm.
        //
        // Ô vuông trên màn vẫn giữ vai trò hướng dẫn người dùng đưa mã vào giữa, không cần
        // ép thành ràng buộc cứng.

        let orientation: CGImagePropertyOrientation = .right // camera sau, thiết bị dọc
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        do {
            try handler.perform([request])
        } catch {
            return
        }
        guard let results = request.results,
              let barcode = results.first(where: { $0.symbology == .qr }),
              let payload = barcode.payloadStringValue else { return }

        scanState.markFound()
        Task { @MainActor in self.lastScannedValue = payload }
    }

    /// Cho phép quét lại: xoá cờ "đã tìm thấy" VÀ bảo đảm phiên camera đang chạy.
    ///
    /// Gọi ở hai chỗ: sau một lượt xử lý thất bại, và mỗi khi quay lại màn quét từ màn
    /// chuyển tiền. Thiếu chỗ thứ hai thì quét thành công một lần là màn quét chết hẳn —
    /// camera vẫn chiếu hình nên trông như bình thường, nhưng không frame nào được xử lý.
    func resumeScanning() {
        scanState.reset()
        // Phiên có thể đã dừng khi màn bị đẩy ra sau; `startRunning` trên phiên đang chạy
        // là no-op nên gọi thẳng không cần kiểm tra.
        Task.detached { [session] in
            if !session.isRunning { session.startRunning() }
        }
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
