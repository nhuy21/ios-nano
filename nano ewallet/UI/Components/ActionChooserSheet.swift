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

    @State private var pickedAppId: String?
    @State private var amountText = ""
    @State private var errorMessage: String?

    @Environment(\.openURL) private var openURL

    private static let brand = Color(hex: 0x00A85E)

    private var amount: Int64 { amountText.amountValue }
    private var canContinue: Bool { pickedAppId != nil && amount > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nạp ví nhanh")
                .font(AppFont.beVietnamPro(16, .bold))
                .foregroundStyle(AppColor.payInk)
                .padding(.horizontal, 20)

            Text("Chọn ngân hàng bạn đang có tiền")
                .font(AppFont.beVietnamPro(12))
                .foregroundStyle(AppColor.payMuted)
                .padding(.horizontal, 20)
                .padding(.vertical, 2)

            Spacer().frame(height: 10)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(QuickTopUpDeeplink.supportedBanks) { bank in
                        bankRow(bank)
                    }
                }
            }
            // Trần chiều cao để danh sách + ô tiền + nút vẫn nằm gọn trong màn máy nhỏ.
            .frame(maxHeight: 320)

            amountField

            if let errorMessage {
                Text(errorMessage)
                    .font(AppFont.beVietnamPro(12, .medium))
                    .foregroundStyle(AppColor.error)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

            continueButton
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

    private func bankRow(_ bank: QuickTopUpDeeplink.SourceBank) -> some View {
        let isPicked = pickedAppId == bank.appId
        return HStack(spacing: 14) {
            BankAppIcon(bank: bank)

            Text(bank.displayName)
                .font(AppFont.beVietnamPro(15, .semibold))
                .foregroundStyle(AppColor.payInk)

            Spacer(minLength: 0)

            if isPicked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Self.brand)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(isPicked ? Self.brand.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .pressable {
            pickedAppId = bank.appId
            errorMessage = nil
        }
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Số tiền")
                .font(AppFont.beVietnamPro(12, .semibold))
                .foregroundStyle(AppColor.payMuted)

            HStack(spacing: 8) {
                TextField("", text: $amountText, prompt: .appPlaceholder("0"))
                    .font(AppFont.beVietnamPro(18, .bold))
                    .foregroundStyle(AppColor.payInk)
                    .keyboardType(.numberPad)
                    .tint(Self.brand)
                    .thousandsSeparated($amountText)

                Text("đ")
                    .font(AppFont.beVietnamPro(16, .semibold))
                    .foregroundStyle(AppColor.payMuted)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(AppColor.bgSoft)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var continueButton: some View {
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
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private func openBankApp() {
        guard let pickedAppId, amount > 0 else { return }
        guard let url = QuickTopUpDeeplink.buildURL(sourceAppId: pickedAppId, amount: amount) else {
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
