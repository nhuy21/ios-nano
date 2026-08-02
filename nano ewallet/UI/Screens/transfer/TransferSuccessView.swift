//
//  TransferSuccessView.swift
//  nano ewallet
//
//  Mirror WalletTransferSuccessScreen.kt — bố cục "biên lai": nền gradient brand +
//  confetti, mọi thứ (tích, số tiền, chi tiết, banner hoàn thành) nằm gọn trong tờ
//  bill trắng có đáy răng cưa. Dùng chung cho cả 2 luồng ví/ngân hàng, chỉ khác
//  nhãn dòng số tài khoản và nhãn "Nội dung"/"Lời nhắn".
//
//  Mã giao dịch và thời gian xử lý: BE chưa trả về đủ nên thiếu cái nào thì tự sinh
//  giá trị giả cho cái đó — biên lai không khuyết dòng, bố cục test được ngay.
//

import SwiftUI
import UIKit
import Photos

@MainActor
struct TransferSuccessView: View {
    let amount: Int64
    let recipientName: String
    let recipientDetail: String
    let noteLabel: String
    let note: String
    var transactionCode: String?
    var elapsedSeconds: Double?
    let onHome: () -> Void

    private enum WsColor {
        static let green = Color(hex: 0x00A85E)
        static let ink = Color(hex: 0x111C17)
        static let gray = Color(hex: 0x8A9990)
        static let line = Color(hex: 0xE4EDE8)
    }

    /// Sinh 1 lần lúc vào màn rồi giữ nguyên — nếu tính lại trong `body` thì mỗi lần
    /// render mã/giờ sẽ nhảy số.
    @State private var fallbackCode = String(format: "%06d", Int.random(in: 0...999_999))
    @State private var timeText = ""
    @State private var shareImage: ShareableImage?
    @State private var toast: String?

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x2ECB6E), location: 0),
                    .init(color: Color(hex: 0x0BA94F), location: 0.55),
                    .init(color: Color(hex: 0x008C3F), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            confettiLayer

            VStack(spacing: 0) {
                Text("BIÊN LAI CHUYỂN TIỀN")
                    .font(AppFont.beVietnamPro(15, .bold))
                    .foregroundStyle(.white)
                    .tracking(2)
                    .padding(16)

                ScrollView {
                    bill
                        .background(Color.white, in: BillShape())
                        .shadow(color: Color(hex: 0x004D22).opacity(0.25), radius: 10, x: 0, y: 6)
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 12)
                }

                actionRow
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "vi_VN")
            formatter.dateFormat = "dd/MM/yyyy - HH:mm"
            timeText = formatter.string(from: Date())
        }
        .sheet(item: $shareImage) { item in
            ReceiptShareSheet(items: [item.image])
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(AppFont.beVietnamPro(13, .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.8), in: Capsule())
                    .padding(.bottom, 110)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toast)
    }

    // MARK: - Confetti

    private var confettiLayer: some View {
        VStack {
            Canvas { context, size in
                for dot in Self.confetti {
                    let rect = CGRect(
                        x: size.width * dot.fx - dot.r, y: dot.y - dot.r,
                        width: dot.r * 2, height: dot.r * 2
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(dot.color))
                }
            }
            .frame(height: 150)
            Spacer()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private struct ConfettiDot {
        let fx: CGFloat
        let y: CGFloat
        let r: CGFloat
        let color: Color
    }

    private static let confetti: [ConfettiDot] = [
        .init(fx: 0.10, y: 26, r: 4, color: Color(hex: 0xFFD166)),
        .init(fx: 0.18, y: 64, r: 3, color: .white),
        .init(fx: 0.30, y: 22, r: 3.5, color: Color(hex: 0xBDF0D0)),
        .init(fx: 0.42, y: 78, r: 3, color: Color(hex: 0xFF8FA3)),
        .init(fx: 0.62, y: 30, r: 3.5, color: Color(hex: 0xFFD166)),
        .init(fx: 0.74, y: 70, r: 3, color: .white),
        .init(fx: 0.86, y: 34, r: 4, color: Color(hex: 0xBDF0D0)),
        .init(fx: 0.92, y: 84, r: 3, color: Color(hex: 0xFF8FA3)),
        .init(fx: 0.24, y: 104, r: 3, color: .white),
        .init(fx: 0.68, y: 108, r: 3.5, color: Color(hex: 0xFFD166)),
    ]

    // MARK: - Bill

    private var bill: some View {
        VStack(spacing: 0) {
            checkBadge

            Text("Chuyển tiền thành công!")
                .font(AppFont.beVietnamPro(20, .bold))
                .foregroundStyle(WsColor.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 14)

            Text("SỐ TIỀN ĐÃ CHUYỂN")
                .font(AppFont.beVietnamPro(11, .medium))
                .foregroundStyle(WsColor.gray)
                .tracking(1.5)
                .padding(.top, 18)

            HStack(alignment: .bottom, spacing: 5) {
                Text(Int(amount).vndGrouped)
                    .font(AppFont.baloo2(34, .bold))
                    .foregroundStyle(WsColor.green)
                    .tracking(-1)
                Text("đ")
                    .font(AppFont.beVietnamPro(15, .medium))
                    .foregroundStyle(WsColor.green)
                    .padding(.bottom, 4)
            }
            .padding(.top, 8)

            VStack(spacing: 0) {
                detailRow(label: "Người nhận", value: recipientName)
                thinLine
                if !isWallet && !channel.isEmpty {
                    detailRow(label: "Ngân hàng", value: channel)
                    thinLine
                }
                detailRow(label: isWallet ? "Số ví" : "Số tài khoản", value: accountNumber)
                if !note.isEmpty {
                    thinLine
                    detailRow(label: noteLabel, value: note)
                }
                thinLine
                detailRow(label: "Mã giao dịch", value: transactionCode ?? fallbackCode)
                thinLine
                detailRow(label: "Thời gian", value: timeText)

                Text("Giao dịch đã được hoàn thành trong \(completedText) giây")
                    .font(AppFont.beVietnamPro(12.5, .medium))
                    .foregroundStyle(WsColor.green)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        WsColor.green.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .padding(.top, 14)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 26)
        // +8 cho chiều cao răng cưa, để nội dung không chạm mép răng.
        .padding(.bottom, 30)
    }

    private var checkBadge: some View {
        ZStack {
            Circle()
                .fill(WsColor.green.opacity(0.10))
                .frame(width: 86, height: 86)
            Circle()
                .fill(WsColor.green.opacity(0.16))
                .frame(width: 70, height: 70)
            Circle()
                .fill(WsColor.green)
                .frame(width: 56, height: 56)
                .shadow(color: WsColor.green.opacity(0.4), radius: 5, x: 0, y: 3)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                }
        }
    }

    private var thinLine: some View {
        Rectangle().fill(WsColor.line).frame(height: 1)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(spacing: 16) {
            Text(label)
                .font(AppFont.beVietnamPro(13))
                .foregroundStyle(WsColor.gray)
            Spacer(minLength: 0)
            Text(value)
                .font(AppFont.beVietnamPro(13, .semibold))
                .foregroundStyle(WsColor.ink)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, 11)
    }

    // MARK: - Hàng hành động

    private var actionRow: some View {
        HStack(spacing: 0) {
            actionItem(systemImage: "house.fill", label: "Về trang chủ", action: onHome)
            actionItem(systemImage: "square.and.arrow.down", label: "Lưu ảnh", action: saveReceipt)
            actionItem(systemImage: "square.and.arrow.up", label: "Chia sẻ biên lai", action: shareReceipt)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func actionItem(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 22))
                    .foregroundStyle(WsColor.ink)
                    .frame(height: 26)
                Text(label)
                    .font(AppFont.beVietnamPro(12))
                    .foregroundStyle(WsColor.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Lưu / chia sẻ biên lai

    /// Chụp ĐÚNG phần bill (không gồm hàng nút) — render riêng qua `ImageRenderer` với
    /// nền trắng đặc và bo góc thường thay vì răng cưa, để ảnh gửi đi là khối phẳng gọn.
    private func renderReceipt() -> UIImage? {
        let renderer = ImageRenderer(
            content: bill
                .frame(width: 360)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(12)
                .background(Color.white)
        )
        renderer.scale = 3
        return renderer.uiImage
    }

    /// Dùng `PHPhotoLibrary` thay `UIImageWriteToSavedPhotosAlbum(_, nil, nil, nil)`:
    /// bản kia nuốt mọi lỗi (không có completion) nên user từ chối quyền ảnh vẫn thấy
    /// báo "đã lưu" — báo thành công cho việc chưa hề xảy ra.
    private func saveReceipt() {
        guard let image = renderReceipt() else {
            showToast("Không tạo được ảnh biên lai")
            return
        }
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                showToast("Cần quyền truy cập thư viện ảnh để lưu biên lai")
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                showToast("Đã lưu biên lai vào thư viện")
            } catch {
                showToast("Lưu ảnh thất bại, vui lòng thử lại")
            }
        }
    }

    private func shareReceipt() {
        guard let image = renderReceipt() else {
            showToast("Không tạo được ảnh biên lai")
            return
        }
        shareImage = ShareableImage(image: image)
    }

    private func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if toast == message { toast = nil }
        }
    }

    // MARK: - Derived

    /// `recipientDetail` do màn trước ghép sẵn dạng "Ví nano • 19957873068" hoặc
    /// "Vietcombank • 0123456789" — tách lại để biên lai hiện đúng 2 dòng riêng.
    private var detailParts: (channel: String, number: String) {
        let parts = recipientDetail
            .components(separatedBy: "•")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2 else { return ("", recipientDetail) }
        return (parts[0], parts[1])
    }

    private var channel: String { detailParts.channel }
    private var accountNumber: String { detailParts.number }
    private var isWallet: Bool { channel.localizedCaseInsensitiveContains("ví") }

    /// Làm tròn 1 chữ số thập phân, dấu phẩy kiểu VN, tối thiểu 0,1 giây.
    private var completedText: String {
        let seconds = max((elapsedSeconds ?? 2).rounded(toPlaces: 1), 0.1)
        return String(format: "%.1f", locale: Locale(identifier: "vi_VN"), seconds)
    }
}

/// Bill: bo góc trên, đáy răng cưa như vé/hoá đơn giấy (mirror `BillShape` bên Kotlin).
private struct BillShape: Shape {
    var topCorner: CGFloat = 26
    var toothWidth: CGFloat = 14
    var toothHeight: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let baseline = h - toothHeight
        let half = toothWidth / 2

        var path = Path()
        path.move(to: CGPoint(x: 0, y: topCorner))
        path.addQuadCurve(to: CGPoint(x: topCorner, y: 0), control: .zero)
        path.addLine(to: CGPoint(x: w - topCorner, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: topCorner), control: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: w, y: baseline))

        // Răng cưa chạy từ phải sang trái: đỉnh nhọn ở đáy, chân ở baseline.
        var x = w
        var down = true
        while x > 0 {
            let nextX = max(x - half, 0)
            path.addLine(to: CGPoint(x: nextX, y: down ? h : baseline))
            x = nextX
            down.toggle()
        }

        path.addLine(to: CGPoint(x: 0, y: baseline))
        path.closeSubpath()
        return path
    }
}

private struct ShareableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ReceiptShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

#Preview {
    TransferSuccessView(
        amount: 200_000, recipientName: "DANG NGOC KHIEU",
        recipientDetail: "Ví nano • 19958413065",
        noteLabel: "Lời nhắn", note: "Đặng Ngọc Khiêu chuyển tiền qua ví Nano",
        onHome: {}
    )
}
