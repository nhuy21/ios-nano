//
//  ActionChooserSheet.swift
//  nano ewallet
//
//  Port Dialog "Nạp/Rút ví" + hàng `PasteSourceRow` trong HomeScreen.kt — thẻ trắng bo
//  góc, tiêu đề + phụ đề, rồi các dòng thao tác có icon tròn và mô tả.
//
//  Android KHÔNG dùng menu hệ thống ở đây, nên iOS cũng không dùng confirmationDialog
//  (menu đó chỉ có mỗi tiêu đề nút, mất hẳn phần icon và dòng mô tả).
//

import SwiftUI

/// "Nạp ví nhanh" — chọn app ngân hàng đang có tiền, nhập số tiền, rồi mở thẳng app đó với
/// số tài khoản VA của ví điền sẵn. Khác luồng QR thường ở chỗ người dùng không phải tự copy
/// số tài khoản dán sang app ngân hàng nữa, chỉ cần xác nhận.
///
/// Số tiền là BẮT BUỘC (không phải để cho đẹp): thiếu nó thì dl.vietqr.io không sinh mã, app
/// ngân hàng mở lên đứng ở màn chính — xem `QuickTopUpDeeplink`.
struct QuickTopUpSheet: View {
    let onDismiss: () -> Void
    /// Đã mở app ngân hàng — nơi gọi bắt đầu theo dõi tiền về.
    let onOpenedBankApp: () -> Void

    /// Bước đang đứng. Hai bước RỜI NHAU như Kotlin (`QuickTopUpBankPickerDialog`): chọn
    /// bank xong mới sang ô nhập tiền, không bày cả hai trong một thẻ.
    ///
    /// Gộp bank đã chọn vào chính case `.amount` thay vì để một biến `pickedAppId` riêng —
    /// nhờ vậy không tồn tại trạng thái "đang ở bước nhập tiền mà chưa có bank".
    private enum Step: Equatable {
        case pickBank
        case amount(appId: String)
    }

    @State private var step: Step = .pickBank
    /// Bàn phím số có đang mở không. Mở SẴN khi vừa sang bước nhập tiền (việc đầu tiên và
    /// duy nhất ở đó là gõ số), phím "Tiếp" đóng lại để thấy trọn nút "Mở app ngân hàng",
    /// chạm lại ô tiền thì mở ra.
    @State private var isAmountFocused = false
    @State private var amountText = ""
    @State private var errorMessage: String?

    @Environment(\.openURL) private var openURL

    private static let brand = Color(hex: 0x00A85E)

    private var amount: Int64 { amountText.amountValue }
    private var canContinue: Bool { amount > 0 }

    var body: some View {
        ZStack {
            // Chạm nền mờ ở bước nhập tiền thì LÙI về chọn bank, không đóng hẳn — mirror
            // Kotlin (`onDismiss` của `AmountInputDialog` chỉ xoá bank đã chọn). Đóng thẳng
            // thì lỡ tay một cái là mất luôn bank vừa chọn.
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { backOrDismiss() }

            // Thẻ trắng canh GIỮA phần màn còn lại (phần chưa bị bàn phím chiếm) — nhờ
            // `safeAreaInset` bên dưới nên nó không bao giờ bị bàn phím đè.
            card
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Bàn phím số nằm NGOÀI thẻ trắng và ghim đáy màn, full width — giống ô số tiền ở màn
        // chuyển ví/chuyển khoản. Để bên trong thẻ thì nó bị thẻ kéo lên giữa màn và thụt vào
        // 28pt hai bên, trông như một khối trôi lơ lửng.
        //
        // Bản 3 cột, KHÔNG có phím hành động: thẻ đã có nút "Mở app ngân hàng" riêng — để cả
        // hai là hai chỗ cho cùng một việc, người dùng không biết chỗ nào mới là bước cuối.
        // Cất bàn phím thì chạm ra ngoài thẻ. Xem `CompactNumericKeypad`.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isAmountFocused {
                CompactNumericKeypad(
                    onDigit: appendDigits,
                    onBackspace: backspaceDigit
                )
            }
        }
    }

    @ViewBuilder
    private var card: some View {
        switch step {
        case .pickBank: bankPickerCard
        case .amount: amountCard
        }
    }

    // MARK: - Bước 1: chọn ngân hàng

    private var bankPickerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nạp ví nhanh")
                .font(AppFont.beVietnamPro(16, .bold))
                .foregroundStyle(AppColor.payInk)
                .padding(.horizontal, 20)

            Text("Chọn app ngân hàng bạn đang có tiền để chuyển vào ví")
                .font(AppFont.beVietnamPro(12))
                .foregroundStyle(AppColor.payMuted)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(QuickTopUpDeeplink.supportedBanks) { bank in
                        bankRow(bank)
                    }
                }
            }
            // Trần chiều cao để danh sách vẫn nằm gọn trong màn máy nhỏ.
            .frame(maxHeight: 360)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func bankRow(_ bank: QuickTopUpDeeplink.SourceBank) -> some View {
        HStack(spacing: 14) {
            BankAppIcon(bank: bank)

            Text(bank.displayName)
                .font(AppFont.beVietnamPro(15, .semibold))
                .foregroundStyle(AppColor.payInk)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        // Sang thẳng bước nhập tiền, KHÔNG đánh dấu chọn rồi chờ bấm nút: bước này chỉ có
        // đúng một việc, thêm một nhịp xác nhận là thừa. Mirror Kotlin.
        .pressable {
            errorMessage = nil
            step = .amount(appId: bank.appId)
            isAmountFocused = true
        }
    }

    // MARK: - Bước 2: nhập số tiền

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Số tiền nạp")
                .font(AppFont.beVietnamPro(16, .bold))
                .foregroundStyle(AppColor.payInk)

            Text("Số tiền sẽ được điền sẵn trong app ngân hàng")
                .font(AppFont.beVietnamPro(12))
                .foregroundStyle(AppColor.payMuted)
                .padding(.top, 4)

            HStack(spacing: 8) {
                Text(amountText.isEmpty ? "0" : Int(amount).vndGrouped)
                    .font(AppFont.beVietnamPro(22, .bold))
                    .foregroundStyle(amountText.isEmpty ? AppColor.payMuted : AppColor.payInk)

                Spacer(minLength: 0)

                Text("đ")
                    .font(AppFont.beVietnamPro(16, .semibold))
                    .foregroundStyle(AppColor.payMuted)
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(AppColor.bgSoft)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isAmountFocused ? Self.brand : Color.clear, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
            .pressable { isAmountFocused = true }
            .padding(.top, 16)

            suggestionRow

            if let errorMessage {
                Text(errorMessage)
                    .font(AppFont.beVietnamPro(12, .medium))
                    .foregroundStyle(AppColor.error)
                    .padding(.top, 8)
            }

            Button(action: openBankApp) {
                Text("Mở app ngân hàng")
                    .font(AppFont.beVietnamPro(15, .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Self.brand.opacity(canContinue ? 1 : 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!canContinue)
            .padding(.top, 16)

            // Gọi `backToBankPicker` chứ KHÔNG `backOrDismiss`: hàm kia ưu tiên đóng bàn phím
            // nên bấm lần đầu sẽ chỉ cất bàn phím, không khớp với nhãn nút.
            Button(action: backToBankPicker) {
                Text("Chọn ngân hàng khác")
                    .font(AppFont.beVietnamPro(14, .semibold))
                    .foregroundStyle(AppColor.payMuted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Gợi ý số tiền

    /// Số mức gợi ý hiện cùng lúc.
    private static let suggestionCount = 4
    /// Gợi ý luôn từ hàng nghìn trở lên — nạp ví vài trăm đồng là vô nghĩa.
    private static let minSuggestion: Int64 = 1_000
    /// Chưa gõ gì thì bày các mức nạp hay dùng.
    private static let defaultSuggestions: [Int64] = [10_000, 20_000, 50_000, 100_000]

    /// Trần số tiền, khớp giới hạn 9 chữ số của `appendDigits` — gợi ý vượt trần thì bấm vào
    /// sẽ điền một số mà gõ tay không bao giờ nhập được.
    private static let maxSuggestion: Int64 = 999_999_999

    /// Gợi ý theo số ĐANG GÕ: nhân dần với 10 rồi bỏ các mức dưới 1.000, lấy 4 mức đầu.
    ///
    /// Gõ "25" -> 2.500 / 25.000 / 250.000 / 2.500.000 (bắt đầu từ ×100).
    /// Gõ "5"  -> ×100 mới được 500, chưa đủ 4 chữ số nên bị bỏ, dãy thành
    ///            5.000 / 50.000 / 500.000 / 5.000.000.
    private var suggestions: [Int64] {
        let typed = amountText.amountValue
        guard typed > 0 else { return Self.defaultSuggestions }

        var result: [Int64] = []
        // Bắt đầu từ ×100 cho MỌI số, rồi mới lọc mức dưới 1.000. Nếu để ×10 làm mốc thì
        // "100" ra 1.000 (đủ 1.000 ngay từ bước đầu) trong khi "25" ra 2.500 — cùng một
        // thao tác gõ mà bậc nhảy khác nhau.
        var value = typed * 100
        // Trần 12 vòng: đủ để leo từ 1 lên hàng nghìn tỷ, và chặn lặp vô hạn nếu số vào quá
        // lớn khiến không mức nào lọt qua bộ lọc.
        for _ in 0..<12 where result.count < Self.suggestionCount {
            guard value <= Self.maxSuggestion else { break }
            if value >= Self.minSuggestion { result.append(value) }
            value *= 10
        }
        return result
    }

    @ViewBuilder
    private var suggestionRow: some View {
        let values = suggestions
        // Gõ số quá lớn thì không còn mức nào hợp lệ — ẩn hẳn hàng, để lại `padding` là chừa
        // một dải trống không rõ vì sao.
        if !values.isEmpty {
            // Cuộn ngang: 4 mức tiền hàng triệu là quá rộng so với thẻ trên máy nhỏ.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(values, id: \.self) { value in
                        Text(Int(value).vndGrouped)
                            .font(AppFont.beVietnamPro(13, .semibold))
                            .foregroundStyle(AppColor.payInk)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(AppColor.bgSoft)
                            .clipShape(Capsule())
                            .contentShape(Capsule())
                            .pressable { pickSuggestion(value) }
                    }
                }
            }
            .padding(.top, 10)
        }
    }

    private func pickSuggestion(_ value: Int64) {
        amountText = String(value)
        errorMessage = nil
        // Cất bàn phím luôn: chọn xong một mức là đã có số tiền, việc kế tiếp là bấm nút mở
        // app chứ không gõ thêm.
        isAmountFocused = false
    }

    // MARK: - Nhập số

    private func appendDigits(_ digits: String) {
        // Chặn số 0 dẫn đầu và giới hạn 9 chữ số như màn chuyển tiền ví.
        let combined = amountText.isEmpty && digits.allSatisfy { $0 == "0" }
            ? ""
            : amountText + digits
        amountText = String(combined.prefix(9))
        errorMessage = nil
    }

    private func backspaceDigit() {
        guard !amountText.isEmpty else { return }
        amountText.removeLast()
    }

    /// Chạm ra ngoài: bàn phím đang mở thì đóng bàn phím trước (như mọi ô nhập liệu khác),
    /// rồi mới tới lùi về chọn bank, cuối cùng mới đóng hẳn.
    private func backOrDismiss() {
        guard case .amount = step else {
            onDismiss()
            return
        }
        if isAmountFocused {
            isAmountFocused = false
            return
        }
        backToBankPicker()
    }

    /// Lùi hẳn về bước chọn ngân hàng, bỏ số tiền đang gõ dở.
    private func backToBankPicker() {
        amountText = ""
        errorMessage = nil
        isAmountFocused = false
        step = .pickBank
    }

    private func openBankApp() {
        guard case .amount(let appId) = step, amount > 0 else { return }
        guard let url = QuickTopUpDeeplink.buildURL(sourceAppId: appId, amount: amount) else {
            // Chỉ xảy ra khi ví chưa có số tài khoản VA — báo thẳng thay vì mở app ngân hàng
            // rồi để người dùng đối diện một màn trống không hiểu vì sao.
            errorMessage = "Ví chưa có số tài khoản nhận tiền. Vui lòng thử lại sau."
            return
        }
        // Báo TRƯỚC khi rời app: nơi gọi cần chốt mốc số dư ngay lúc này, vì tiền có thể về
        // trong lúc người dùng còn đang ở app ngân hàng.
        onOpenedBankApp()
        openURL(url)
        onDismiss()
    }
}

/// Icon app ngân hàng, tải bằng `URLSession` chứ KHÔNG dùng `AsyncImage`.
///
/// `AsyncImage` nằm trong `fullScreenCover` bị huỷ dở lúc lớp phủ đang chuyển cảnh và không
/// bao giờ thử lại — kết quả là danh sách trống logo mãi, dù mở đúng URL đó bằng Safari trên
/// cùng máy vẫn ra ảnh. Tự tải thì kiểm soát được vòng đời, và có cache để mở lại sheet
/// không phải tải lần nữa.
///
/// Trong lúc chờ (và khi mạng hỏng hẳn) hiện logo vector local theo BIN, nên ô icon không bao
/// giờ trống chỗ.
private struct BankAppIcon: View {
    let bank: QuickTopUpDeeplink.SourceBank
    var size: CGFloat = 52

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                // `scaledToFill` (= ContentScale.Crop bên Kotlin): icon App Store là ảnh
                // VUÔNG có nền riêng, fit vào vòng tròn sẽ hở bốn góc nền trắng.
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                localFallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        // Viền mảnh để icon nền trắng (VietinBank, ACB...) vẫn tách khỏi nền trắng của sheet.
        .overlay {
            Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        }
        .task(id: bank.appId) { await load() }
    }

    /// Hiện trong lúc ảnh chưa về (và khi mạng hỏng hẳn) nên ô icon không bao giờ trống chỗ.
    /// Vector local port từ Android đã bỏ màu gốc nên chỉ tô được một màu mực.
    private var localFallback: some View {
        Color.white
            .overlay {
                if let shape = BankLogoPaths.shape(bin: bank.bin) {
                    ZStack {
                        ForEach(Array(shape.paths.enumerated()), id: \.offset) { _, pathData in
                            SVGPath(pathData: pathData, viewBox: shape.viewBox)
                                .fill(AppColor.payInk, style: FillStyle(eoFill: shape.usesEvenOdd))
                        }
                    }
                    .frame(width: size * 0.55, height: size * 0.55)
                } else {
                    Text(bank.displayName.prefix(1))
                        .font(AppFont.beVietnamPro(18, .bold))
                        .foregroundStyle(AppColor.payInk)
                }
            }
    }

    private func load() async {
        guard let url = URL(string: bank.logoUrl) else { return }
        // `URLSession.shared` đã tự cache theo `URLCache` mặc định, mà response của Apple có
        // `Cache-Control: max-age` rất dài — nên không cần tự dựng thêm một lớp cache nữa.
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let loaded = UIImage(data: data) else {
            // Tải hỏng thì cứ để vector local — không có gì thêm phải làm.
            return
        }
        image = loaded
    }
}

struct ActionChooserSheet: View {
    let title: String
    let subtitle: String
    let actions: [Action]
    let onDismiss: () -> Void

    struct Action: Identifiable {
        let id = UUID()
        let systemImage: String
        let title: String
        let subtitle: String
        let handler: () -> Void
    }

    private static let brand = Color(hex: 0x00A85E)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(AppFont.beVietnamPro(16, .bold))
                .foregroundStyle(AppColor.payInk)
                .padding(.horizontal, 20)

            Text(subtitle)
                .font(AppFont.beVietnamPro(12))
                .foregroundStyle(AppColor.payMuted)
                .padding(.horizontal, 20)
                .padding(.vertical, 2)

            Spacer().frame(height: 10)

            ForEach(actions) { action in
                Button {
                    onDismiss()
                    action.handler()
                } label: {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(Self.brand.opacity(0.12))
                            .frame(width: 40, height: 40)
                            .overlay {
                                Image(systemName: action.systemImage)
                                    .font(.system(size: 20))
                                    .foregroundStyle(Self.brand)
                            }

                        VStack(alignment: .leading, spacing: 0) {
                            Text(action.title)
                                .font(AppFont.beVietnamPro(14, .semibold))
                                .foregroundStyle(AppColor.payInk)
                            Text(action.subtitle)
                                .font(AppFont.beVietnamPro(12))
                                .foregroundStyle(AppColor.payMuted)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
        )
    }
}
