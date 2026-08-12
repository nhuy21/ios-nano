//
//  TransactionDetailView.swift
//  nano ewallet
//
//  Chi tiết giao dịch — mirror TransactionDetailScreen.kt. Trước đây là bottom sheet,
//  nay là màn riêng push vào `NavigationStack`: sheet không đủ chỗ cho biên lai và bị
//  thanh điều hướng hệ thống che mất nút Đóng ở cuối.
//

import SwiftUI
import UIKit

struct TransactionDetailView: View {
    let tx: TransactionEntity
    let onBack: () -> Void

    @StateObject private var toast = ToastState()
    // `@ObservedObject` chứ không `@StateObject`: đây là singleton sống sẵn ngoài view,
    // không phải thứ view này sở hữu và tạo ra.
    @ObservedObject private var authStore = AuthStore.shared
    @ObservedObject private var wallet = WalletStore.shared

    @State private var showInfo = false
    @State private var shareItem: ReceiptImage?
    @State private var isRendering = false

    private enum TxColor {
        static let divider = Color(hex: 0xE7ECEA)
        static let rowBg = Color(hex: 0xF6F7F9)
        static let green = Color(hex: 0x00A85E)
        static let coin = Color(hex: 0xF6B21B)
        static let saveBg = Color(hex: 0xE6F7EE)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            bottomBar
        }
        .screenBackground(Color.white)
        .toast(toast, bottomPadding: 24)
        .sheet(item: $shareItem) { item in
            ReceiptShareSheet(items: [item.image])
        }
        .overlay {
            if showInfo {
                TxInfoDialog(
                    statusText: TransactionDisplay.statusMeta(for: tx).text,
                    showTransIdHint: tx.kind != .topUp,
                    onDismiss: { showInfo = false }
                )
            }
        }
    }

    // MARK: - Header

    /// Tự dựng thay `DetailHeader` vì cần thêm nút (i) ở mép phải.
    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(AppColor.payInk)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Quay lại")

            Spacer(minLength: 0)

            Text("Chi tiết giao dịch")
                .font(AppFont.beVietnamPro(18, .bold))
                .foregroundStyle(AppColor.payInk)

            Spacer(minLength: 0)

            Button {
                showInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(AppColor.payMuted)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Thông tin hỗ trợ")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Nội dung cuộn

    private var content: some View {
        ScrollView {
            receipt
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
                .background(Color.white)
        }
    }

    /// - Parameters:
    ///   - animated: `false` khi render ra ảnh. `ImageRenderer` dựng một cây view MỚI nằm
    ///     ngoài màn hình, nên `@State` giữ toạ độ hai đầu bị khởi tạo lại về `nil` và vạch
    ///     nối + đồng xu biến mất khỏi ảnh. Bản tĩnh vẽ thẳng vạch nối, không cần đo.
    ///   - showsSaveButton: `false` khi render — nút bấm không nên nằm trong biên lai gửi đi
    ///     (bản Android cũng đặt nút này ngoài vùng chụp).
    private func receiptBody(animated: Bool, showsSaveButton: Bool) -> some View {
        VStack(spacing: 0) {
            Text("Tổng tiền")
                .font(AppFont.beVietnamPro(14))
                .foregroundStyle(AppColor.payMuted)
                .padding(.top, 8)

            Text(signedAmount)
                .font(AppFont.beVietnamPro(38, .heavy))
                .foregroundStyle(TransactionDisplay.amountColor(for: tx))
                .padding(.top, 6)

            statusBadge
                .padding(.top, 10)

            TxPartyCard(
                tx: tx,
                myName: myName,
                myWalletNumber: wallet.bkUsername,
                dateText: dateText,
                timeText: timeText,
                animated: animated
            )
            .padding(.top, 18)

            Text("Thông tin chuyển khoản")
                .font(AppFont.beVietnamPro(16, .bold))
                .foregroundStyle(AppColor.payInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 22)
                .padding(.bottom, 4)

            infoRows

            if let description = tx.description, !description.isEmpty {
                noteBlock(description)
                    .padding(.top, 18)
            }

            if showsSaveButton {
                SaveToContactsButton(tx: tx, toast: toast)
                    .padding(.top, 18)
            }
        }
    }

    private var receipt: some View {
        receiptBody(animated: true, showsSaveButton: true)
    }

    private var infoRows: some View {
        VStack(spacing: 0) {
            // Thứ tự mirror TransactionDetailScreen.kt — mã giao dịch trước, rồi tiền/phí/
            // tổng, sau mới tới thông tin phân loại.
            //
            // NẠP VÍ thì ẨN mã giao dịch: tiền vào ví qua tài khoản VA (người dùng tự chuyển
            // từ app ngân hàng khác) nên mã ở đây là mã nội bộ Bảo Kim, KHÔNG phải mã họ tra
            // soát được ở ngân hàng của mình — hiện ra chỉ gây nhầm khi đối chiếu.
            if tx.kind != .topUp {
                detailRow(label: "Mã giao dịch", value: "#" + (tx.bkTransId ?? tx.id))
                dashedDivider
            }
            detailRow(label: "Số tiền", value: Int(tx.amountValue).vndFormatted)
            dashedDivider
            // "0đ" chứ không phải "Miễn phí": biên lai là chứng từ, ghi đúng con số.
            detailRow(label: "Phí giao dịch", value: Int(tx.feeValue).vndFormatted)
            dashedDivider
            detailRow(
                label: "Tổng cộng",
                value: Int(tx.amountValue + tx.feeValue).vndFormatted,
                valueColor: TxColor.green
            )
            dashedDivider
            detailRow(label: "Loại giao dịch", value: TransactionDisplay.typeLabel(for: tx))

            if let bankName = tx.benBankName, !bankName.isEmpty {
                dashedDivider
                detailRow(label: "Ngân hàng", value: bankName)
            }

            if let balanceAfter = tx.cachedBalanceAfterValue {
                dashedDivider
                detailRow(label: "Số dư sau giao dịch", value: Int(balanceAfter).vndFormatted)
            }
        }
    }

    /// Nội dung chuyển khoản tách thành khối riêng có viền, không nhét chung vào hàng
    /// nhãn-giá trị: câu nội dung thường dài, để ở cột phải sẽ xuống dòng lỗ chỗ.
    private func noteBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nội dung")
                .font(AppFont.beVietnamPro(14))
                .foregroundStyle(AppColor.payMuted)

            Text(text)
                .font(AppFont.beVietnamPro(14, .medium))
                .foregroundStyle(AppColor.payInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(TxColor.divider, lineWidth: 1)
                }
        }
    }

    private var statusBadge: some View {
        let meta = TransactionDisplay.statusMeta(for: tx)
        return HStack(spacing: 6) {
            Image(systemName: statusIcon)
                .font(.system(size: 16))
            Text(meta.text)
                .font(AppFont.beVietnamPro(13, .bold))
        }
        .foregroundStyle(meta.color)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(meta.background)
        .clipShape(Capsule())
    }

    private var statusIcon: String {
        switch tx.statusKind {
        case .success: return "checkmark.circle.fill"
        case .failed, .cancelled: return "xmark.circle.fill"
        default: return "clock.fill"
        }
    }

    /// Nét đứt thay đường liền — mirror `DashedDivider` bên Kotlin (nét 10, khoảng hở 8).
    private var dashedDivider: some View {
        Line()
            .stroke(
                TxColor.divider,
                style: StrokeStyle(lineWidth: 1, dash: [10, 8])
            )
            .frame(height: 1)
    }

    private func detailRow(
        label: String,
        value: String,
        valueColor: Color = AppColor.payInk
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(AppFont.beVietnamPro(13))
                .foregroundStyle(AppColor.payMuted)
                // `minWidth` chứ không phải bề rộng cố định: nhãn dài như "Số dư sau giao
                // dịch" bị ép xuống dòng nếu khoá cứng 130.
                .frame(minWidth: 96, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(value)
                .font(AppFont.beVietnamPro(13, .semibold))
                .foregroundStyle(valueColor)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 9)
    }

    // MARK: - Thanh nút đáy

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(action: shareReceipt) {
                Text(isRendering ? "Đang tạo ảnh..." : "Chia sẻ")
                    .font(AppFont.beVietnamPro(15, .bold))
                    .foregroundStyle(AppColor.brand)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(AppColor.brand, lineWidth: 1.5)
                    }
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(isRendering)

            Button(action: onBack) {
                Text("Đóng")
                    .font(AppFont.beVietnamPro(15, .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColor.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color.white)
    }

    /// Chụp ĐÚNG phần biên lai (không gồm thanh nút đáy) để nút không lọt vào ảnh.
    ///
    /// Render là việc nặng và đồng bộ; chạy thẳng trong `action` của nút thì giao diện đứng
    /// im cho tới lúc xong, nhãn "Đang tạo ảnh..." không kịp vẽ ra. Nhường một nhịp cho
    /// SwiftUI vẽ trạng thái chờ trước rồi mới render.
    private func shareReceipt() {
        guard !isRendering else { return }
        isRendering = true
        Task { @MainActor in
            await Task.yield()
            defer { isRendering = false }
            let renderer = ImageRenderer(
                content: receiptBody(animated: false, showsSaveButton: false)
                    .frame(width: 360)
                    .padding(16)
                    .background(Color.white)
            )
            renderer.scale = 3
            guard let image = renderer.uiImage else {
                toast.show("Không tạo được ảnh biên lai")
                return
            }
            shareItem = ReceiptImage(image: image)
        }
    }

    // MARK: - Dữ liệu

    /// Tên hiển thị cho đầu "ví của tôi" trong thẻ hai bên.
    private var myName: String {
        authStore.userFullName ?? "Ví của tôi"
    }

    private var signedAmount: String {
        let signed = tx.isIncome ? tx.amountValue : -tx.amountValue
        return Int(signed).vndSigned
    }

    private var createdDate: Date? {
        ISO8601DateFormatter.withFractionalSeconds.date(from: tx.createdAt)
            ?? ISO8601DateFormatter.standard.date(from: tx.createdAt)
    }

    private var dateText: String {
        guard let createdDate else { return "" }
        return DateFormatter.app("dd/MM/yyyy").string(from: createdDate)
    }

    private var timeText: String {
        guard let createdDate else { return "" }
        return DateFormatter.app("HH:mm").string(from: createdDate)
    }
}

/// Ảnh biên lai chờ chia sẻ — bọc thành kiểu `Identifiable` để dùng với `.sheet(item:)`.
private struct ReceiptImage: Identifiable {
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

/// Đường thẳng ngang — dùng để vẽ nét đứt (`Divider` không nhận `StrokeStyle`).
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return path
    }
}

// MARK: - Thẻ hai đầu gửi/nhận

/// Hai đầu của giao dịch (gửi ở trên, nhận ở dưới) nối nhau bằng một vạch dọc có đồng xu
/// chạy từ trên xuống — cùng chiều đọc, tiền rời người gửi rồi tới người nhận.
///
/// Nhãn vai trò đổi theo loại giao dịch chứ không cứng "Người gửi/Người nhận": nạp tiền và
/// rút tiền có một đầu là ngân hàng hoặc chính ví mình, gọi là "người" thì sai.
private struct TxPartyCard: View {
    let tx: TransactionEntity
    let myName: String
    let myWalletNumber: String?
    let dateText: String
    let timeText: String
    /// `false` khi đang render ra ảnh — xem `receiptBody(animated:showsSaveButton:)`.
    var animated: Bool = true

    /// Tâm hai vòng tròn, đo thật vì chiều cao hàng đổi theo cỡ chữ hệ thống và độ dài tên.
    @State private var topCenter: CGPoint?
    @State private var bottomCenter: CGPoint?

    private static let divider = Color(hex: 0xE7ECEA)
    private static let green = Color(hex: 0x00A85E)

    var body: some View {
        VStack(spacing: 0) {
            TxPartyRow(
                party: srcParty,
                label: labels.src,
                isDestination: false,
                // Chỉ MỘT hàng hiện thời gian, hai hàng cùng hiện là lặp. Thời gian gắn với
                // hàng đích (lúc tiền tới) nên nằm ở hàng dưới.
                dateText: "",
                timeText: "",
                animated: animated,
                onCenter: { topCenter = $0 }
            )

            Rectangle()
                .fill(Self.divider)
                .frame(height: 1)

            TxPartyRow(
                party: destParty,
                label: labels.dest,
                isDestination: true,
                dateText: dateText,
                timeText: timeText,
                animated: animated,
                onCenter: { bottomCenter = $0 }
            )
        }
        .coordinateSpace(name: Self.space)
        .background {
            // Vẽ SAU lưng nội dung để vạch không đè lên chữ.
            if animated {
                if let topCenter, let bottomCenter {
                    // `from`/`to` là toạ độ thuần: xu nội suy from.y -> to.y. Nguồn ở trên
                    // nên `from` là tâm hàng trên, xu chạy xuống hàng đích.
                    CoinFlowConnector(from: topCenter, to: bottomCenter)
                }
            } else {
                // Bản tĩnh cho ảnh: không đo được toạ độ (view nằm ngoài màn hình) nên vẽ
                // vạch chạy dọc theo đúng cột chứa hai vòng tròn — 14pt padding + nửa cột
                // 30pt = 29pt tính từ mép trái.
                staticConnector
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Self.divider, lineWidth: 1)
        }
    }

    static let space = "TxPartyCard"

    /// Vạch nối tĩnh dùng cho ảnh biên lai: chạy giữa hai vòng tròn, chừa 25pt mỗi đầu để
    /// không đâm vào chúng.
    private var staticConnector: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Self.green.opacity(0.35))
                .frame(width: 2)
                .padding(.vertical, 25)
                .offset(x: 28)
            Spacer(minLength: 0)
        }
    }

    /// `(dest, src)` — nhãn vai trò theo loại giao dịch, mirror `partyLabels(type)`.
    private var labels: (dest: String, src: String) {
        switch tx.kind {
        case .topUp: return ("Vào ví", "Nguồn nạp")
        case .withdraw: return ("Đến ngân hàng", "Từ ví")
        case .refund: return ("Vào ví", "Nguồn hoàn tiền")
        default: return ("Người nhận", "Người gửi")
        }
    }

    /// Ví mình luôn nằm ở đầu NHẬN khi tiền vào, và ở đầu GỬI khi tiền ra.
    private var myParty: TxParty {
        TxParty(name: myName, channel: "Ví Nano", number: myWalletNumber, isBank: false)
    }

    private var otherParty: TxParty {
        TxParty(
            name: tx.benAccName ?? "—",
            channel: tx.benBankName ?? "Ví Nano",
            number: tx.benAccNo,
            isBank: tx.benBankName != nil
        )
    }

    private var destParty: TxParty { tx.isIncome ? myParty : otherParty }
    private var srcParty: TxParty { tx.isIncome ? otherParty : myParty }
}

private struct TxParty {
    let name: String
    let channel: String
    let number: String?
    let isBank: Bool
}

private struct TxPartyRow: View {
    let party: TxParty
    let label: String
    /// Đầu nhận — vòng tròn nảy lên và chuyển vàng lúc đồng xu chạy tới.
    let isDestination: Bool
    let dateText: String
    let timeText: String
    let animated: Bool
    let onCenter: (CGPoint) -> Void

    private static let green = Color(hex: 0x00A85E)
    private static let coin = Color(hex: 0xF6B21B)

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    Text(party.name)
                        .font(AppFont.beVietnamPro(15, .bold))
                        .foregroundStyle(AppColor.payInk)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)

                    // Ngày và giờ xuống hai dòng riêng: gộp một dòng thì tên người nhận dài
                    // sẽ bị ép ngắn lại nhường chỗ.
                    if !dateText.isEmpty {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(dateText)
                            Text(timeText)
                        }
                        .font(AppFont.beVietnamPro(12.5))
                        .foregroundStyle(AppColor.payMuted)
                        .fixedSize()
                    }
                }

                if let number = party.number, !number.isEmpty {
                    Text("\(party.channel) • \(number)")
                        .font(AppFont.beVietnamPro(13))
                        .foregroundStyle(AppColor.payMuted)
                        .padding(.top, 2)
                } else {
                    Text(party.channel)
                        .font(AppFont.beVietnamPro(13))
                        .foregroundStyle(AppColor.payMuted)
                        .padding(.top, 2)
                }

                Text(label)
                    .font(AppFont.beVietnamPro(13))
                    .foregroundStyle(AppColor.payMuted)
                    .padding(.top, 4)
            }
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var avatar: some View {
        // Spacer 12pt phía trên để vòng tròn thẳng hàng với dòng tên, không phải giữa hàng.
        VStack(spacing: 0) {
            Spacer().frame(height: 12)
            // Chỉ đầu NHẬN mới cần nhịp đồng hồ (để nảy lúc đồng xu tới); đầu gửi vẽ tĩnh
            // để không bắt SwiftUI dựng lại view mỗi khung hình một cách vô ích.
            if isDestination && animated {
                TimelineView(.animation) { timeline in
                    circle(bump: Self.bump(at: timeline.date))
                }
            } else {
                circle(bump: 0)
            }
            Spacer(minLength: 0)
        }
    }

    private func circle(bump: CGFloat) -> some View {
        Circle()
            .strokeBorder(circleTint(bump), lineWidth: 1.5)
            .background(
                Circle().fill(
                    isDestination ? Self.coin.opacity(0.14 * bump) : Color.clear
                )
            )
            .frame(width: 26, height: 26)
            .overlay {
                Image(systemName: party.isBank ? "building.columns" : "wallet.pass")
                    .font(.system(size: 13))
                    .foregroundStyle(circleTint(bump))
            }
            .scaleEffect(1 + 0.34 * bump)
            .background {
                // Báo vị trí tâm lên thẻ cha để vẽ vạch nối đúng hai đầu.
                GeometryReader { geo in
                    // `initial: true` thay cho `onAppear`: đọc `geo` lúc onAppear có thể
                    // trúng nhịp layout chưa chốt, báo về toạ độ (0,0) rồi mới sửa lại.
                    Color.clear
                        .onChangeCompat(
                            of: geo.frame(in: .named(TxPartyCard.space)),
                            initial: true
                        ) { _, frame in
                            onCenter(CGPoint(x: frame.midX, y: frame.midY))
                        }
                }
            }
    }

    /// Nảy lên rồi xẹp xuống trong 15% cuối chu kỳ — đúng lúc đồng xu chạm tới đầu nhận.
    private static func bump(at date: Date) -> CGFloat {
        let duration: Double = 2.2
        let p = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration) / duration
        guard p > 0.85 else { return 0 }
        return CGFloat(sin((p - 0.85) / 0.15 * .pi))
    }

    /// Xanh -> vàng khi đồng xu tới. Nội suy thẳng trên RGB của `#00A85E` và `#F6B21B`.
    private func circleTint(_ bump: CGFloat) -> Color {
        guard isDestination, bump > 0 else { return Self.green }
        return Color(
            red: lerp(0x00 / 255, 0xF6 / 255, bump),
            green: lerp(0xA8 / 255, 0xB2 / 255, bump),
            blue: lerp(0x5E / 255, 0x1B / 255, bump)
        )
    }

    private func lerp(_ a: Double, _ b: Double, _ t: CGFloat) -> Double {
        a + (b - a) * Double(t)
    }

}

// MARK: - Vạch nối + đồng xu

/// Vạch dọc nối hai đầu, có đồng xu vàng chạy từ đầu gửi lên đầu nhận rồi lặp lại.
///
/// Vạch bị CẮT một khoảng quanh đồng xu: đồng xu là icon rỗng ruột (chỉ có nét viền), để
/// vạch chạy xuyên qua thì nhìn như bị xiên que.
private struct CoinFlowConnector: View {
    let from: CGPoint
    let to: CGPoint

    private static let duration: Double = 2.2
    private static let coinSize: CGFloat = 18
    private static let green = Color(hex: 0x00A85E)
    private static let coin = Color(hex: 0xF6B21B)

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, _ in
                let progress = Self.progress(at: timeline.date)
                let coinY = from.y + (to.y - from.y) * progress
                let gap = Self.coinSize * 0.62

                draw(&context, coinY: coinY, gap: gap, progress: progress)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(
        _ context: inout GraphicsContext,
        coinY: CGFloat,
        gap: CGFloat,
        progress: Double
    ) {
        let x = from.x
        // Mờ dần ở 8% đầu và cuối để đồng xu không xuất hiện/biến mất đột ngột.
        let fade = min(1, min(progress, 1 - progress) / 0.08)

        // Vạch trên và dưới đồng xu, chừa khoảng hở ở giữa.
        let stroke = StrokeStyle(lineWidth: 2, lineCap: .round)
        let shading = GraphicsContext.Shading.color(Self.green.opacity(0.35))

        // Kẹp theo mút TRÊN/DƯỚI chứ không theo `from`/`to`: xu chạy xuôi hay ngược đều
        // dùng chung hàm này, mà bám vào `from`/`to` thì một chiều sẽ cho đoạn dài âm và
        // mất sạch vạch nối.
        let topY = min(from.y, to.y)
        let bottomY = max(from.y, to.y)

        // Chỉ vẽ khi đoạn còn đủ dài: đầu nét bo tròn nên đoạn dài 0 vẫn ra một chấm 2pt
        // lơ lửng ở đầu vạch lúc đồng xu chạy tới sát hai mút.
        let upperEnd = max(topY, coinY - gap)
        if upperEnd - topY > 0.5 {
            var upper = Path()
            upper.move(to: CGPoint(x: x, y: topY))
            upper.addLine(to: CGPoint(x: x, y: upperEnd))
            context.stroke(upper, with: shading, style: stroke)
        }

        let lowerStart = min(bottomY, coinY + gap)
        if bottomY - lowerStart > 0.5 {
            var lower = Path()
            lower.move(to: CGPoint(x: x, y: lowerStart))
            lower.addLine(to: CGPoint(x: x, y: bottomY))
            context.stroke(lower, with: shading, style: stroke)
        }

        let center = CGPoint(x: x, y: coinY)

        // Quầng sáng: vẽ lại chính hình đồng xu rồi làm nhoè, thay vì tô một gradient tròn.
        // Gradient tròn phủ kín cả vùng giữa nên ra một mảng vàng đặc, nhìn thành vệt đục
        // chứ không phải ánh sáng; còn nhoè theo đúng nét thì sáng lan ra từ chính nét xu.
        // Lớp nhoè nằm trong `drawLayer` riêng để bộ lọc không dính sang vạch nối.
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: 5))
            drawCoin(&glow, center: center, opacity: fade * 0.45)
        }

        drawCoin(&context, center: center, opacity: fade * 0.8)
    }

    /// Đồng xu: vòng tròn + chữ "S" xuyên qua, thuần nét viền (mirror `ic_coin_flow.xml`,
    /// viewport 24 nên mọi toạ độ dưới đây quy theo tỉ lệ 1/24).
    private func drawCoin(_ context: inout GraphicsContext, center: CGPoint, opacity: Double) {
        let s = Self.coinSize / 24
        let color = GraphicsContext.Shading.color(Self.coin.opacity(opacity))
        let stroke = StrokeStyle(lineWidth: 2 * s, lineCap: .round, lineJoin: .round)

        let radius = 9 * s
        context.stroke(
            Path(ellipseIn: CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2
            )),
            with: color,
            style: stroke
        )

        // Chữ "S" dựng bằng hai cung nối nhau + nét dọc xuyên tâm.
        var sPath = Path()
        let left = center.x - 3 * s
        let right = center.x + 3 * s
        sPath.move(to: CGPoint(x: right - 0.2 * s, y: center.y - 3 * s))
        sPath.addCurve(
            to: CGPoint(x: left, y: center.y - 1 * s),
            control1: CGPoint(x: right - 2 * s, y: center.y - 4.2 * s),
            control2: CGPoint(x: left, y: center.y - 4 * s)
        )
        sPath.addCurve(
            to: CGPoint(x: right, y: center.y + 1 * s),
            control1: CGPoint(x: left, y: center.y + 1.6 * s),
            control2: CGPoint(x: right, y: center.y - 1.6 * s)
        )
        sPath.addCurve(
            to: CGPoint(x: left + 0.2 * s, y: center.y + 3 * s),
            control1: CGPoint(x: right, y: center.y + 4 * s),
            control2: CGPoint(x: left + 2 * s, y: center.y + 4.2 * s)
        )
        context.stroke(sPath, with: color, style: stroke)

        var bar = Path()
        bar.move(to: CGPoint(x: center.x, y: center.y - 5 * s))
        bar.addLine(to: CGPoint(x: center.x, y: center.y + 5 * s))
        context.stroke(bar, with: color, style: stroke)
    }

    /// Vị trí đồng xu trong chu kỳ hiện tại, 0 = đầu gửi, 1 = đầu nhận.
    ///
    /// Tính từ đồng hồ của `TimelineView` thay vì nuôi một `@State` riêng: không có state
    /// nghĩa là không có gì để lệch nhịp khi view được dựng lại.
    private static func progress(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration)
        return t / duration
    }
}

// MARK: - Lưu vào danh bạ

/// Chỉ hiện với giao dịch VÍ (`benAccNo` có mà `benBankName` không) — người nhận ngân hàng
/// đã có luồng lưu riêng ở màn chuyển tiền.
private struct SaveToContactsButton: View {
    let tx: TransactionEntity
    @ObservedObject var toast: ToastState

    @ObservedObject private var store = BeneficiaryStore.shared

    @State private var isEditing = false
    @State private var nickname = ""
    @State private var isSaving = false

    private var canSave: Bool {
        !isSaving && !nickname.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        if let accNo = tx.benAccNo, !accNo.isEmpty, tx.benBankName == nil {
            content(accNo: accNo)
                // Nạp danh bạ nếu phiên này chưa từng tải: vào thẳng màn chi tiết từ push
                // hay từ Lịch sử thì cache còn rỗng, không kiểm tra được đã lưu hay chưa nên
                // nút "Lưu vào danh bạ" hiện ra cả với người đã có trong danh bạ.
                .task { _ = await store.get() }
        }
    }

    @ViewBuilder
    private func content(accNo: String) -> some View {
        if store.beneficiaries.contains(where: { $0.benUsername == accNo || $0.accNo == accNo }) {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(AppColor.brand)
                Text("Đã có trong danh bạ")
                    .font(AppFont.beVietnamPro(13.5, .semibold))
                    .foregroundStyle(AppColor.payMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else if isEditing {
            VStack(spacing: 10) {
                TextField("", text: $nickname, prompt: .appPlaceholder("Tên gợi nhớ (vd: Chị Yến kế toán)"))
                    .font(AppFont.beVietnamPro(14))
                    .foregroundStyle(AppColor.payInk)
                    .tint(AppColor.brand)
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(Color(hex: 0xF3F6F4))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onChangeNewCompat(of: nickname) { value in
                        if value.count > 40 { nickname = String(value.prefix(40)) }
                    }

                Button {
                    Task { await save(accNo: accNo) }
                } label: {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView().tint(AppColor.brand)
                        } else {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 18))
                                .foregroundStyle(AppColor.brand)
                        }
                        Text(isSaving ? "Đang lưu..." : "Lưu vào danh bạ")
                            .font(AppFont.beVietnamPro(15, .bold))
                            .foregroundStyle(AppColor.brand)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    // Mờ đi khi chưa nhập tên, để thấy ngay là chưa bấm được.
                    .background(Color(hex: 0xE6F7EE).opacity(canSave ? 1 : 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                // Tên gợi nhớ rỗng thì danh bạ hiện ra một dòng trống, không tra được ai —
                // mirror `canSave` bên Kotlin.
                .disabled(!canSave)
            }
        } else {
            Button {
                nickname = tx.benAccName ?? ""
                isEditing = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 18))
                    Text("Lưu vào danh bạ")
                        .font(AppFont.beVietnamPro(15, .bold))
                }
                .foregroundStyle(AppColor.brand)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Color(hex: 0xE6F7EE))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
        }
    }

    private func save(accNo: String) async {
        isSaving = true
        defer { isSaving = false }
        do {
            let trimmed = nickname.trimmingCharacters(in: .whitespaces)
            _ = try await store.create(
                CreateBeneficiaryRequest(
                    type: .wallet,
                    bankNo: nil,
                    accNo: nil,
                    // Tên thật trên ví vẫn gửi kèm để danh bạ còn đối chiếu được với người
                    // nhận, dù người dùng đã đặt tên gợi nhớ riêng.
                    accName: tx.benAccName,
                    benUsername: accNo,
                    nickname: trimmed.isEmpty ? nil : trimmed
                )
            )
            isEditing = false
            toast.show("Đã lưu vào danh bạ")
        } catch {
            toast.show("Không lưu được, vui lòng thử lại")
        }
    }
}

// MARK: - Dialog hỗ trợ

private struct TxInfoDialog: View {
    let statusText: String
    /// `false` với nạp ví — màn đó không hiện mã giao dịch, nên hướng dẫn "liên hệ kèm mã
    /// giao dịch" chỉ khiến người dùng đi tìm một thứ không có trên màn hình.
    var showTransIdHint: Bool = true
    let onDismiss: () -> Void

    private static let supportPhone = "0986995079"

    private var guidance: String {
        showTransIdHint
            ? "Mã giao dịch là căn cứ để tra soát. Nếu thấy sai lệch, hãy chụp lại màn hình này (nút Chia sẻ) và liên hệ hỗ trợ kèm mã giao dịch."
            : "Nếu thấy sai lệch, hãy chụp lại màn hình này (nút Chia sẻ) và liên hệ hỗ trợ."
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 0) {
                Text("Về giao dịch này")
                    .font(AppFont.beVietnamPro(17, .bold))
                    .foregroundStyle(AppColor.payInk)

                Text("Trạng thái hiện tại: \(statusText).\n\n" + guidance)
                    .font(AppFont.beVietnamPro(14))
                    .foregroundStyle(AppColor.payMuted)
                    .padding(.top, 10)

                Text("Hỗ trợ: \(Self.supportPhone)")
                    .font(AppFont.beVietnamPro(14, .bold))
                    .foregroundStyle(AppColor.brand)
                    .padding(.top, 16)

                Button(action: onDismiss) {
                    Text("Đã hiểu")
                        .font(AppFont.beVietnamPro(15, .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColor.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.top, 18)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 40)
        }
    }
}

#Preview {
    TransactionDetailView(
        tx: TransactionEntity(
            id: "abc123",
            type: "TRANSFER_IN",
            amount: "500000",
            fee: "0",
            description: "Chuyển tiền sinh nhật",
            cachedBalanceAfter: "12000000",
            bkTransId: "BK123456",
            benBankNo: nil,
            benAccNo: nil,
            benAccName: "Nguyễn Văn A",
            benBankName: nil,
            status: "SUCCESS",
            createdAt: "2026-07-31T10:24:00.000Z"
        ),
        onBack: {}
    )
}
