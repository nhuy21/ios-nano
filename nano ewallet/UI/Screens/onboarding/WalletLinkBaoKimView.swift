//
//  WalletLinkBaoKimView.swift
//  nano ewallet
//
//  Mirror WalletLinkBaoKimScreen.kt — nhập họ tên + số ví Bảo Kim để đồng bộ vào Ví
//  nano, thay cho luồng eKYC khi người dùng chọn "Đồng bộ từ ví Bảo Kim".
//
//  Lỗi Bảo Kim từ chối ngay tại request này (ví không tồn tại, ví khoá, SĐT đã liên
//  kết, tên không khớp) đẩy ra `onError` để màn ngoài mở màn báo lỗi riêng, KHÔNG hiện
//  chữ đỏ tại chỗ — giống Android.
//

import SwiftUI

struct WalletLinkBaoKimView: View {
    let onBack: () -> Void
    let onSubmit: (_ embedLink: String) -> Void
    let onError: (_ message: String) -> Void

    @State private var fullName = ""
    @State private var walletNo = ""
    @State private var isSubmitting = false
    @FocusState private var focusedField: Field?

    private enum Field { case fullName, walletNo }

    private var canSubmit: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty
            && !walletNo.trimmingCharacters(in: .whitespaces).isEmpty
            && !isSubmitting
    }

    var body: some View {
        VStack(spacing: 0) {
            BackHeader(action: onBack)
                .padding(.top, 12)
                .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 12)

                    baoKimBadge

                    Spacer().frame(height: 20)

                    Text("Liên kết ví Bảo Kim")
                        .font(AppFont.beVietnamPro(24, .bold))
                        .foregroundStyle(AppColor.payInk)

                    Spacer().frame(height: 6)

                    Text("Nhập thông tin ví Bảo Kim của bạn để đồng bộ vào Ví nano.")
                        .font(AppFont.beVietnamPro(14))
                        .foregroundStyle(AppColor.payMuted)
                        .multilineTextAlignment(.center)

                    Spacer().frame(height: 28)

                    labeledField(
                        label: "Họ và tên",
                        text: $fullName,
                        placeholder: "NGUYEN VAN A",
                        field: .fullName
                    )

                    Spacer().frame(height: 16)

                    labeledField(
                        label: "Số ví Bảo Kim",
                        text: $walletNo,
                        placeholder: "Nhập số ví",
                        field: .walletNo,
                        keyboard: .numberPad
                    )
                }
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)

            consentText
                .padding(.vertical, 14)

            PrimaryButton(
                title: "Liên kết ví",
                loadingTitle: "Đang liên kết...",
                isLoading: isSubmitting,
                isEnabled: canSubmit,
                action: submit
            )
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 20)
        .background(Color.white)
        // Số ví dùng bàn phím số của hệ thống nên không có nút Done — chạm ra ngoài để
        // đóng (cử chỉ ở tầng UIWindow, xem DismissKeyboardOnTap).
        .contentShape(Rectangle())
    }

    private var baoKimBadge: some View {
        Circle()
            .fill(Color(hex: 0xE3F1FF))
            .frame(width: 88, height: 88)
            .overlay {
                Image("logo_baokim")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 52, height: 52)
            }
    }

    private func labeledField(
        label: String,
        text: Binding<String>,
        placeholder: String,
        field: Field,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(AppFont.beVietnamPro(14, .semibold))
                .foregroundStyle(AppColor.payInk)

            TextField(placeholder, text: text)
                .font(AppFont.beVietnamPro(16))
                .foregroundStyle(AppColor.payInk)
                .tint(AppColor.brand)
                .keyboardType(keyboard)
                .textInputAutocapitalization(field == .fullName ? .characters : .never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: field)
                .frame(height: 56)
                .padding(.horizontal, 16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            focusedField == field ? AppColor.brand : AppColor.payInputBorder,
                            lineWidth: 1
                        )
                }
                .onChange(of: text.wrappedValue) { _, newValue in
                    // Số ví chỉ nhận chữ số — bàn phím số vẫn gõ được dấu chấm/phẩy trên
                    // vài bố cục bàn phím, và dán từ clipboard thì lọt mọi ký tự.
                    guard field == .walletNo else { return }
                    let digits = newValue.filter(\.isNumber)
                    if digits != newValue { text.wrappedValue = digits }
                }
        }
    }

    /// `AttributedString` thay `Text + Text` (deprecated iOS 26) — đoạn dài nhiều dòng nên
    /// phải giữ trong MỘT `Text` để wrap đúng, không dùng HStack được.
    private var consentText: some View {
        func segment(_ text: String, highlighted: Bool) -> AttributedString {
            var part = AttributedString(text)
            part.foregroundColor = highlighted ? AppColor.brand : AppColor.payMuted
            if highlighted { part.font = AppFont.beVietnamPro(12.5, .semibold) }
            return part
        }

        var result = segment(
            "Bằng việc liên kết ví, bạn đồng ý cho Ví nano truy cập và quản lý thông tin ví Bảo Kim của bạn theo ",
            highlighted: false
        )
        result += segment("Điều khoản sử dụng", highlighted: true)
        result += segment(" và ", highlighted: false)
        result += segment("Chính sách bảo mật", highlighted: true)
        result += segment(".", highlighted: false)

        return Text(result)
            .font(AppFont.beVietnamPro(12.5))
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func submit() {
        guard canSubmit else { return }
        focusedField = nil
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                let result = try await OnboardingService.linkBaoKimWallet(
                    username: walletNo.trimmingCharacters(in: .whitespaces),
                    fullName: fullName.trimmingCharacters(in: .whitespaces)
                )
                onSubmit(result.embedLink)
            } catch let error as APIError {
                onError(error.message)
            } catch {
                onError("Kết nối đến hệ thống thất bại, vui lòng thử lại sau")
            }
        }
    }
}

#Preview {
    WalletLinkBaoKimView(onBack: {}, onSubmit: { _ in }, onError: { _ in })
}
