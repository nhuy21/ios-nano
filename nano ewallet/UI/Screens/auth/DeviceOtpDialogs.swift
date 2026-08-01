//
//  DeviceOtpDialogs.swift
//  nano ewallet
//
//  Mirror DeviceOtpDialogs.kt — 2 dialog dùng chung giữa LoginView và WelcomeBackView
//  khi tài khoản đang đăng nhập ở máy khác (login trả về requireDeviceOtp + loginTicket).
//
//  Palette riêng của dialog (không lấy từ AppColor — Android cũng hardcode riêng ở file này).
//

import SwiftUI

private enum DialogColor {
    static let green = Color(hex: 0x00A85E)
    static let ink = Color(hex: 0x111C17)
    static let muted = Color(hex: 0x8A9990)
    static let err = Color(hex: 0xC0392B)
    static let dotBorder = Color(hex: 0xD9C9BD)
}

/// Bước 1: hỏi user có đồng ý đăng xuất thiết bị khác để đăng nhập máy này không.
struct DeviceConflictDialog: View {
    let sending: Bool
    let onDismiss: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Tài khoản đang đăng nhập ở thiết bị khác")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(DialogColor.ink)

            Text("Mỗi tài khoản chỉ dùng được trên 1 thiết bị. Bạn có muốn gửi mã OTP để đăng xuất thiết bị kia và đăng nhập trên máy này không?")
                .font(.system(size: 13))
                .foregroundStyle(DialogColor.muted)
                .lineSpacing(6)
                .padding(.top, 8)

            HStack(spacing: 10) {
                Button {
                    onDismiss()
                } label: {
                    Text("Huỷ")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DialogColor.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(AppColor.bgSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(sending)

                Button {
                    onConfirm()
                } label: {
                    Text(sending ? "Đang gửi…" : "Gửi mã OTP")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(DialogColor.green.opacity(sending ? 0.5 : 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(sending)
            }
            .padding(.top, 20)
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 24)
        .interactiveDismissDisabled(sending)
    }
}

/// Bước 2: nhập OTP SMS để xác nhận đăng xuất thiết bị khác + đăng nhập máy này.
struct DeviceOtpDialog: View {
    let loginTicket: String
    let phone: String?
    let onDismiss: () -> Void
    let onSuccess: (AuthService.AuthOutcome) -> Void

    @State private var otp = ""
    @State private var verifying = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            Text("Nhập mã OTP")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(DialogColor.ink)

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(DialogColor.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            HStack(spacing: 14) {
                ForEach(0..<6, id: \.self) { index in
                    let filled = index < otp.count
                    Circle()
                        .fill(filled ? DialogColor.green : Color.clear)
                        .overlay {
                            if !filled {
                                Circle().strokeBorder(DialogColor.dotBorder, lineWidth: 2)
                            }
                        }
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.top, 20)

            Group {
                if verifying {
                    Text("Đang xác thực…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DialogColor.muted)
                } else if let errorText {
                    Text(errorText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DialogColor.err)
                        .multilineTextAlignment(.center)
                } else {
                    Color.clear.frame(height: 18)
                }
            }
            .padding(.top, 12)
            .frame(minHeight: 18)

            DialogKeypad(
                disabled: verifying,
                onDigit: { digit in
                    guard otp.count < 6 else { return }
                    otp.append(digit)
                },
                onBackspace: { if !otp.isEmpty { otp.removeLast() } },
                onCancel: onDismiss
            )
            .padding(.top, 16)
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 24)
        .interactiveDismissDisabled(verifying)
        .onChange(of: otp) { _, newValue in
            if newValue.count == 6 { submit() }
        }
    }

    private var subtitle: String {
        if let phone {
            return "Mã xác thực đã gửi tới \(maskPhone(phone))"
        }
        return "Mã xác thực đã gửi tới số điện thoại của bạn"
    }

    /// Mirror `maskPhone` riêng của DeviceOtpDialogs.kt: `84387600501` → `"843****0501"`.
    private func maskPhone(_ phone: String) -> String {
        guard phone.count > 6 else { return phone }
        let prefix = phone.prefix(3)
        let suffix = phone.suffix(4)
        return "\(prefix)****\(suffix)"
    }

    private func submit() {
        guard otp.count == 6, !verifying else { return }
        verifying = true
        errorText = nil
        Task {
            do {
                let outcome = try await AuthService.verifyDeviceOtp(loginTicket: loginTicket, otp: otp)
                verifying = false
                onSuccess(outcome)
            } catch {
                verifying = false
                errorText = (error as? APIError)?.message ?? "Mã OTP không đúng"
                otp = ""
            }
        }
    }
}

/// Bàn phím số dùng riêng cho DeviceOtpDialog — mirror PinDigitKey/PinActionKey.
private struct DialogKeypad: View {
    let disabled: Bool
    let onDigit: (String) -> Void
    let onBackspace: () -> Void
    let onCancel: () -> Void

    private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { digit in
                        digitKey(digit)
                    }
                }
            }
            HStack(spacing: 10) {
                actionKey(label: "⌫", color: DialogColor.green) { onBackspace() }
                digitKey("0")
                actionKey(label: "Huỷ", color: DialogColor.muted, fontSize: 13, weight: .semibold) { onCancel() }
            }
        }
    }

    private func digitKey(_ digit: String) -> some View {
        Button {
            onDigit(digit)
        } label: {
            Text(digit)
                .font(AppFont.baloo2(26, .bold))
                .foregroundStyle(DialogColor.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 62)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: DialogColor.ink.opacity(0.14), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func actionKey(
        label: String,
        color: Color,
        fontSize: CGFloat = 20,
        weight: Font.Weight = .regular,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: fontSize, weight: weight))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .frame(height: 62)
                .background(AppColor.brandSoft)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: AppColor.brand.opacity(0.2), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
