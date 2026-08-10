//
//  ChangePasswordView.swift
//  nano ewallet
//
//  Mirror ChangeSecretScreen.kt — 3 field mật khẩu (PinDotsField) rồi tới OTP 2 bước.
//

import SwiftUI
import Combine

struct ChangePasswordView: View {
    let onBack: () -> Void

    @StateObject private var vm = ChangePasswordViewModel()
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case current, new, confirm, otp }

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(title: "Đổi mật khẩu", onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Mật khẩu đăng nhập gồm 6 chữ số. Không dùng dãy số dễ đoán (123456, ngày sinh...).")
                        .font(AppFont.beVietnamPro(13))
                        .foregroundStyle(AppColor.payMuted)

                    Spacer().frame(height: 16)

                    passwordCard

                    if vm.otpSent {
                        Spacer().frame(height: 16)
                        otpCard
                    }

                    if let submitError = vm.submitError {
                        FieldError(message: submitError)
                            .padding(.top, 8)
                    }

                    Spacer().frame(height: 20)

                    PrimaryButton(
                        title: vm.otpSent ? "Xác nhận" : "Gửi mã OTP",
                        loadingTitle: vm.otpSent ? "Đang xử lý..." : "Đang gửi...",
                        isLoading: vm.isSendingOtp || vm.isSubmitting,
                        isEnabled: vm.canSubmit,
                        action: submit
                    )
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 24) }
        }
        .screenBackground(Color(hex: 0xF7F8FA))
        .alert("Đổi mật khẩu thành công", isPresented: $vm.showSuccess) {
            Button("Xong") { onBack() }
        } message: {
            Text("Thay đổi đã được áp dụng cho lần đăng nhập/giao dịch tiếp theo.")
        }
    }

    private var passwordCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            fieldBlock(label: "Mật khẩu hiện tại", error: vm.currentError) {
                PinDotsField(
                    value: $vm.currentPassword,
                    placeholder: "Nhập mật khẩu hiện tại",
                    hasError: vm.currentError != nil,
                    submitLabel: .next
                ) {
                    focusedField = .new
                }
                .focused($focusedField, equals: .current)
            }

            fieldBlock(label: "Mật khẩu mới", error: vm.newError) {
                PinDotsField(
                    value: $vm.newPassword,
                    placeholder: "Nhập mật khẩu mới",
                    hasError: vm.newError != nil,
                    submitLabel: .next
                ) {
                    focusedField = .confirm
                }
                .focused($focusedField, equals: .new)
            }

            fieldBlock(label: "Xác nhận mật khẩu mới", error: vm.confirmError) {
                PinDotsField(
                    value: $vm.confirmPassword,
                    placeholder: "Nhập lại mật khẩu mới",
                    hasError: vm.confirmError != nil,
                    submitLabel: .done
                ) {
                    Task { await vm.sendOtp() }
                }
                .focused($focusedField, equals: .confirm)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color(hex: 0x784628).opacity(0x14 / 255.0), radius: 6, x: 0, y: 2)
    }

    private var otpCard: some View {
        fieldBlock(label: "Mã OTP (SMS)", error: vm.otpError) {
            PinDotsField(
                value: $vm.otp,
                placeholder: "Nhập mã 6 số",
                hasError: vm.otpError != nil,
                dotsAlignment: .center,
                submitLabel: .done
            ) {
                Task { await vm.confirmChange() }
            }
            .focused($focusedField, equals: .otp)

            Button {
                Task { await vm.resendOtp() }
            } label: {
                Text(vm.isSendingOtp ? "Đang gửi..." : "Không nhận được mã? Gửi lại")
                    .font(AppFont.beVietnamPro(13, .semibold))
                    .foregroundStyle(AppColor.brand)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(vm.isSendingOtp)
            .padding(.top, 8)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color(hex: 0x784628).opacity(0x14 / 255.0), radius: 6, x: 0, y: 2)
    }

    @ViewBuilder
    private func fieldBlock<Content: View>(
        label: String, error: String?, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel(text: label, size: 13)
            content()
            if let error {
                FieldError(message: error, alignment: .leading)
            }
        }
    }

    private func submit() {
        Task {
            if vm.otpSent {
                await vm.confirmChange()
            } else {
                await vm.sendOtp()
            }
        }
    }
}

#Preview {
    ChangePasswordView(onBack: {})
}
