//
//  WelcomeBackView.swift
//  nano ewallet
//
//  Mirror WelcomeBackScreen.kt. Khác Login: dots CĂN GIỮA, không có back button,
//  placeholder chỉ "Mật khẩu" (không phải "Nhập mật khẩu"), lỗi là 1 String? chứ
//  không phải map.
//

import SwiftUI
import Combine

struct WelcomeBackView: View {
    let phone: String
    let onLogin: (_ status: String?) -> Void
    let onUseAnotherAccount: () -> Void
    let onForgotPassword: () -> Void

    @StateObject private var vm = WelcomeBackViewModel()

    private var maskedPhone: String {
        phone.count >= 10 ? "\(phone.prefix(3))****\(phone.suffix(3))" : phone
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 48)

                Image("logo_green")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200)
                    .accessibilityLabel("ví nano")

                Spacer().frame(height: 8)

                greeting

                Spacer().frame(height: 6)

                Text("Nhập thông tin để tiếp tục")
                    .font(AppFont.beVietnamPro(14))
                    .foregroundStyle(AppColor.payMuted)
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 28)

                PinDotsField(
                    value: $vm.password,
                    placeholder: "Mật khẩu",
                    hasError: vm.errorMsg != nil,
                    dotsAlignment: .center,
                    submitLabel: .done,
                    onSubmit: submit
                )

                if let errorMsg = vm.errorMsg {
                    FieldError(message: errorMsg)
                }

                Spacer().frame(height: 12)

                Button("Quên mật khẩu?") {
                    onForgotPassword()
                }
                .buttonStyle(.plain)
                .font(AppFont.beVietnamPro(13, .semibold))
                .foregroundStyle(AppColor.brand)
                .frame(maxWidth: .infinity, alignment: .trailing)

                Spacer().frame(height: 20)

                PrimaryButton(
                    title: "Đăng nhập",
                    loadingTitle: "Đang đăng nhập...",
                    isLoading: vm.isSubmitting,
                    action: submit
                )

                Spacer().frame(height: 20)

                OrDivider()

                Spacer().frame(height: 20)

                Button("Đăng nhập bằng tài khoản khác?") {
                    onUseAnotherAccount()
                }
                .buttonStyle(.plain)
                .font(AppFont.beVietnamPro(14, .semibold))
                .foregroundStyle(AppColor.brand)
                .frame(maxWidth: .infinity)

                Spacer().frame(height: 32)

                Text("Được bảo vệ bởi Ví nano Security Engine™")
                    .font(AppFont.beVietnamPro(11))
                    .foregroundStyle(AppColor.payPlaceholder)

                Spacer().frame(height: 16)
            }
            .padding(.horizontal, 24)
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 24) }
        .background(Color.white)
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $vm.showDeviceConflict) {
            DeviceConflictDialog(
                sending: vm.sendingDeviceOtp,
                onDismiss: vm.dismissDeviceConflict,
                onConfirm: { Task { await vm.confirmDeviceOtp() } }
            )
            .presentationBackground(.clear)
        }
        .sheet(isPresented: $vm.showDeviceOtp) {
            if let ticket = vm.deviceTicket {
                DeviceOtpDialog(
                    loginTicket: ticket,
                    phone: vm.deviceOtpPhone,
                    onDismiss: { vm.showDeviceOtp = false },
                    onSuccess: { outcome in
                        vm.showDeviceOtp = false
                        if case .authenticated(let user) = outcome {
                            onLogin(user?.status)
                        }
                    }
                )
                .presentationBackground(.clear)
            }
        }
    }

    /// Dùng `AttributedString` thay `Text + Text` (deprecated iOS 26) — vẫn là MỘT `Text`
    /// nên câu tự wrap nhiều dòng và canh giữa được, khác `HStack` (không wrap).
    private var greeting: some View {
        var result = AttributedString("Chào mừng ")
        result.foregroundColor = AppColor.payInk

        var phone = AttributedString(maskedPhone)
        phone.foregroundColor = AppColor.brand
        result += phone

        var suffix = AttributedString(" trở lại!")
        suffix.foregroundColor = AppColor.payInk
        result += suffix

        return Text(result)
            .font(AppFont.baloo2(22, .bold))
            .multilineTextAlignment(.center)
    }

    private func submit() {
        Task {
            switch await vm.submit(phone: phone) {
            case .success(let status):
                onLogin(status)
            case .handledByDialog, .failed:
                break
            }
        }
    }
}

#Preview {
    WelcomeBackView(phone: "0387600501", onLogin: { _ in }, onUseAnotherAccount: {}, onForgotPassword: {})
}
