//
//  VoiceCommandOverlay.swift
//  nano ewallet
//
//  Mirror VoiceCommandOverlay.kt — nghe "chuyển 200 nghìn cho Mẹ", khớp danh bạ ví
//  rồi đưa sang màn nhập tiền với người nhận + số tiền điền sẵn.
//
//  KHÔNG tự chuyển tiền: người dùng vẫn xác nhận và nhập PIN ở màn sau.
//

import SwiftUI
import Combine

@MainActor
struct VoiceCommandOverlay: View {
    let onDismiss: () -> Void
    /// Trả thẳng route đích thay vì `WalletTransferDraft`: người nhận có thể là ví HOẶC
    /// ngân hàng, hai màn nhập tiền khác nhau nên nơi gọi không tự suy ra được.
    let onResolved: (HomeRoute) -> Void

    @StateObject private var speech = SpeechRecognizerService()
    @StateObject private var beneficiaryStore = BeneficiaryStore.shared

    @State private var statusMessage: String?
    /// Mic đang ở nhịp phóng to hay chưa — mirror `micScale` bên Android.
    @State private var pulse = false
    /// Vòng sóng đã bắt đầu nở chưa. Tách khỏi `pulse` vì hai animation khác chu kỳ
    /// (0.65s đảo chiều so với 1.8s một hướng), dùng chung một biến thì lệch nhịp.
    @State private var rippleAnimating = false

    /// Cả ví lẫn ngân hàng: nói tên người nhận trong danh bạ nào cũng phải ra, chứ không
    /// chỉ danh bạ ví. Lọc bỏ bản ghi thiếu số đích vì có khớp tên cũng không chuyển được.
    private var transferContacts: [Beneficiary] {
        beneficiaryStore.beneficiaries.filter {
            switch $0.type {
            case .wallet: return !($0.benUsername ?? "").isEmpty
            case .bankAccount: return !($0.accNo ?? "").isEmpty
            }
        }
    }

    private var heard: String { speech.partialText.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { close() }

            panel
                .padding(.horizontal, 28)
                // Chặn tap xuyên xuống lớp nền (chạm trong panel không đóng).
                .onTapGesture {}
        }
        // Bật mic NGAY, không chờ tải danh bạ: `get()` là một lượt gọi mạng, chờ nó xong mới
        // `start()` khiến người dùng nói vào lúc mic chưa mở và mất luôn câu đầu. Danh bạ chỉ
        // cần lúc `handleResult` chạy — tức sau khi đã nghe xong.
        .task { await speech.start() }
        .task { _ = await beneficiaryStore.get() }
        .onDisappear { speech.stop() }
        .onAppear {
            speech.onResult = { candidates in handleResult(candidates) }
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            micIndicator

            Text(title)
                .font(AppFont.beVietnamPro(18, .bold))
                .foregroundStyle(AppColor.payInk)
                .padding(.top, 16)

            Text(bodyText)
                .font(AppFont.beVietnamPro(14))
                .foregroundStyle(bodyIsError ? Color(hex: 0xE5484D) : AppColor.payMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 8)

            // Nghe được chữ NHƯNG không khớp -> hiện cả hai: câu đã nghe ở trên,
            // lý do thất bại ở đây. Nếu gộp một chỗ thì mất một trong hai.
            if let statusMessage, !heard.isEmpty {
                Text(statusMessage)
                    .font(AppFont.beVietnamPro(13))
                    .foregroundStyle(Color(hex: 0xE5484D))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.top, 6)
            }

            HStack(spacing: 12) {
                actionButton(
                    title: "Nói lại",
                    foreground: AppColor.brand,
                    background: AppColor.brand.opacity(0.12)
                ) {
                    statusMessage = nil
                    Task { await speech.start() }
                }

                actionButton(
                    title: "Đóng",
                    foreground: AppColor.payInk,
                    background: Color(hex: 0xF1F3F5),
                    action: close
                )
            }
            .padding(.top, 20)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    // MARK: - Mic + sóng toả

    /// Số vòng sóng và độ lệch pha giữa chúng — 3 vòng cách nhau 1/3 chu kỳ để lúc nào cũng
    /// có một vòng đang toả ra, tạo cảm giác liên tục thay vì nhấp nháy đồng loạt.
    private static let rippleCount = 3
    private static let rippleDuration: Double = 1.8

    /// Mic đập + sóng toả khi đang nghe. Đứng im hoàn toàn khi không nghe — đó chính là
    /// điểm để người dùng phân biệt hai trạng thái.
    private var micIndicator: some View {
        ZStack {
            // Sóng chỉ TỒN TẠI khi đang nghe: dựng sẵn rồi ẩn bằng opacity thì animation
            // `repeatForever` vẫn chạy ngầm, tốn CPU và có thể hiện lại sai pha.
            if speech.isListening {
                ForEach(0..<Self.rippleCount, id: \.self) { index in
                    ripple(delay: Double(index) * Self.rippleDuration / Double(Self.rippleCount))
                }
            }

            Circle()
                .fill(AppColor.brand)
                .frame(width: 76, height: 76)
                .overlay {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white)
                }
                .scaleEffect(pulse ? 1.18 : 1)
        }
        // Chừa chỗ cho vòng sóng lớn nhất (76 * 2.2 ≈ 168) — không chừa thì sóng bị panel
        // cắt cụt vì `ZStack` chỉ rộng bằng mic.
        .frame(width: 168, height: 168)
        // Bám theo `isListening`, KHÔNG phải `.onAppear`: lúc view hiện thì `isListening`
        // còn false (xin quyền micro + khởi động engine là bất đồng bộ), nên bật animation
        // ở `onAppear` sẽ gắn `repeatForever` vào lúc chưa nghe rồi tắt ngay — mic nhảy một
        // nhịp rồi đứng im, đúng lỗi "không thấy khác gì khi tắt mic".
        .onChangeNewCompat(of: speech.isListening, initial: true) { listening in
            guard listening else {
                // Tắt animation trước khi hạ `pulse`, nếu không mic co lại chậm rãi theo
                // nhịp cũ trong khi trạng thái đã là "không nghe".
                withAnimation(.easeOut(duration: 0.2)) { pulse = false }
                return
            }
            withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    /// Một vòng sóng: nở từ mic ra rồi mờ dần. `delay` để 3 vòng lệch pha nhau.
    private func ripple(delay: Double) -> some View {
        Circle()
            .stroke(AppColor.brand.opacity(0.5), lineWidth: 2)
            .frame(width: 76, height: 76)
            .scaleEffect(rippleAnimating ? 2.2 : 1)
            .opacity(rippleAnimating ? 0 : 0.55)
            .animation(
                .easeOut(duration: Self.rippleDuration)
                    .repeatForever(autoreverses: false)
                    .delay(delay),
                value: rippleAnimating
            )
            // Bật ở `onAppear` được vì view này CHỈ được dựng khi đã `isListening` —
            // khác trường hợp của mic ở trên.
            .onAppear { rippleAnimating = true }
    }

    private func actionButton(
        title: String, foreground: Color, background: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.beVietnamPro(15, .bold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: - Trạng thái hiển thị

    /// Đã mở panel nhưng mic chưa mở và cũng chưa có lỗi — tức đang xin quyền micro / khởi
    /// động engine. Trên iOS 26 lần đầu, bước này có thể mất vài giây; không nói gì thì panel
    /// đứng im y như lúc mic đã tắt.
    private var isPreparing: Bool {
        !speech.isListening && speech.errorMessage == nil && statusMessage == nil && heard.isEmpty
    }

    private var title: String {
        if speech.isListening { return "Đang nghe…" }
        if isPreparing { return "Đang chuẩn bị…" }
        return "Trợ lý Ví nano"
    }

    private var bodyText: String {
        if !heard.isEmpty { return heard }
        if let error = speech.errorMessage { return error }
        if let statusMessage { return statusMessage }
        if isPreparing { return "Đang bật micro…" }
        return "Hãy nói, ví dụ: \"chuyển 200 nghìn cho Mẹ\""
    }

    private var bodyIsError: Bool {
        heard.isEmpty && (speech.errorMessage != nil || statusMessage != nil)
    }

    // MARK: - Xử lý

    private func handleResult(_ candidates: [String]) {
        let result = VoiceCommandResolver.resolve(
            candidates: candidates,
            contacts: transferContacts,
            bankName: { BankCache.shared.bank(bin: $0)?.shortName ?? "Ngân hàng" }
        )
        switch result {
        case .wallet(let draft):
            speech.stop()
            onResolved(.walletTransferAmount(draft))
        case .bank(let draft):
            speech.stop()
            onResolved(.bankTransfer(draft: draft))
        case .choose:
            // Không xảy ra ở đây: hộp chọn chỉ sinh ra từ ẢNH có nhiều người nhận, còn luồng
            // này chỉ nhận giọng nói. Vẫn phải khai để `switch` đủ nhánh.
            statusMessage = "Không nhận diện được người nhận, vui lòng thử lại"
        case .failure(let message):
            statusMessage = message
        }
    }

    private func close() {
        speech.stop()
        onDismiss()
    }
}
