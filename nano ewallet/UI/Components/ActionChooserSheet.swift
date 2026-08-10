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
            .frame(maxHeight: 260)

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

    /// Hàng chọn ngân hàng.
    ///
    /// KHÔNG bọc trong `Button { } label: { }`: logo tải qua mạng nằm trong label của Button
    /// thì SwiftUI coi cả cụm là hình vẽ của nút, ảnh bị áp kiểu tô template và vòng tải
    /// không chạy — chỉ thấy ô xám giữ chỗ mãi. Dùng `.pressable` (tự bọc Button ở lớp
    /// ngoài) nên phần nội dung vẫn là view thường.
    private func bankRow(_ bank: QuickTopUpDeeplink.SourceBank) -> some View {
        let isPicked = pickedAppId == bank.appId
        return HStack(spacing: 14) {
            bankLogo(bank)

            Text(bank.displayName)
                .font(AppFont.beVietnamPro(14, .semibold))
                .foregroundStyle(AppColor.payInk)

            Spacer(minLength: 0)

            if isPicked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Self.brand)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(isPicked ? Self.brand.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .pressable {
            pickedAppId = bank.appId
            errorMessage = nil
        }
    }

    private func bankLogo(_ bank: QuickTopUpDeeplink.SourceBank) -> some View {
        AsyncImage(url: URL(string: bank.logoUrl)) { phase in
            switch phase {
            case .success(let image):
                // `scaledToFill` chứ KHÔNG phải `scaledToFit`: đây là ảnh quảng bá App Store
                // 1200x630 (tỉ lệ 1.9) chứ không phải icon vuông — icon thật nằm giữa, hai
                // bên là nền trắng. Fit vào ô 40x40 thì ảnh co còn 40x21 và phần nhìn thấy
                // gần như toàn nền trắng, trên nền sheet trắng thành ra như không có gì.
                // Fill lấp đầy ô vuông rồi cắt bớt hai bên thừa, đúng phần icon còn lại.
                image.resizable().scaledToFill()
            case .failure:
                // Tải hỏng (mất mạng, ảnh đổi địa chỉ) thì hiện chữ đầu của tên ngân hàng —
                // ô xám trơn trông như đang tải dở và người dùng sẽ ngồi đợi mãi.
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Self.brand.opacity(0.12))
                    .overlay {
                        Text(bank.displayName.prefix(1))
                            .font(AppFont.beVietnamPro(16, .bold))
                            .foregroundStyle(Self.brand)
                    }
            default:
                // Đang tải: ô xám giữ chỗ, không dùng spinner — 5 vòng xoay cùng lúc lúc mở
                // sheet trông như đang lỗi.
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(AppColor.line.opacity(0.5))
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        // Viền mảnh để icon nền trắng (VietinBank, ACB...) không lẫn vào nền trắng của sheet.
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(AppColor.line, lineWidth: 1)
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
