//
//  OtpView.swift
//  nano ewallet
//
//  Mirror OtpScreen.kt. Sửa bug đã xác nhận: Android có `append()` rỗng ở
//  OtpScreen.kt:295 khiến subtitle mất câu dẫn — bản này hiện đầy đủ
//  "Mã xác thực đã gửi tới {phone che}".
//

import SwiftUI
import Combine

struct OtpView: View {
    let phone: String
    let onBack: () -> Void
    let onVerified: () -> Void

    @StateObject private var vm = OtpViewModel()
    @FocusState private var isFocused: Bool
    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            sheetContent
        }
        .background(Color.white)
        .onAppear {
            isFocused = true
            vm.startCountdown()
        }
        .onChange(of: vm.otp) { _, newValue in
            if newValue.count == OtpViewModel.otpLength {
                submit()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppColor.payInk)
                        .frame(width: 36, height: 36)
                        .background(Color.white)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quay lại")

                Spacer()

                Text("Bước 1 / 3")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.payMuted)
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)

            Spacer().frame(height: 24)

            OtpStepBar(step: 1)
                .padding(.horizontal, 24)

            Spacer().frame(height: 24)

            VStack(alignment: .leading, spacing: 8) {
                Text("Xác thực OTP")
                    .font(AppFont.beVietnamPro(28, .bold))
                    .foregroundStyle(AppColor.payInk)

                // Sửa bug: hiện đầy đủ câu dẫn thay vì chỉ SĐT trần.
                HStack(spacing: 0) {
                    Text("Mã xác thực đã gửi tới ")
                        .font(AppFont.beVietnamPro(13))
                        .foregroundStyle(AppColor.payMuted)
                    Text(maskedPhone)
                        .font(AppFont.beVietnamPro(14, .bold))
                        .foregroundStyle(AppColor.payInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 24)
    }

    private var sheetContent: some View {
        VStack(spacing: 0) {
            otpBoxes
                .padding(.top, 8)

            errorOrSpacer
                .padding(.top, 12)

            // Khoảng trống CO GIÃN, không cố định 60: bàn phím đóng/mở làm chiều cao
            // khả dụng thay đổi, phần dôi ra phải dồn vào đây chứ không được đẩy các ô
            // nhập đi chỗ khác.
            Spacer(minLength: 60)

            confirmButton
                .padding(.bottom, 16)

            resendRow
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        // `.top`: neo các ô nhập ngay dưới header. Thiếu tham số này thì mặc định căn
        // giữa, và mỗi lần bàn phím ẩn là cả khối trôi xuống.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .clipShape(.rect(topLeadingRadius: 28, topTrailingRadius: 28))
    }

    private var otpBoxes: some View {
        ZStack {
            TextField("", text: $vm.otp)
                .keyboardType(.numberPad)
                .focused($isFocused)
                .opacity(0)
                .frame(width: 1, height: 1)

            HStack(spacing: 10) {
                ForEach(0..<OtpViewModel.otpLength, id: \.self) { index in
                    otpBox(at: index)
                }
            }
            .offset(x: shakeOffset)
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }

    private func otpBox(at index: Int) -> some View {
        let digit = digitAt(index)
        let isActive = index == vm.otp.count && !vm.hasError
        let borderColor: Color = {
            if vm.hasError { return AppColor.error }
            if isActive { return AppColor.brand }
            if digit != nil { return AppColor.line }
            return AppColor.payInputBorder
        }()

        return RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(vm.hasError ? AppColor.errorSoft : Color.white)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1.5)
            }
            .overlay {
                if let digit {
                    Text(String(digit))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(vm.hasError ? AppColor.error : AppColor.ink)
                } else if isActive {
                    Rectangle()
                        .fill(AppColor.brand)
                        .frame(width: 2, height: 26)
                }
            }
            .frame(height: 60)
    }

    private func digitAt(_ index: Int) -> Character? {
        guard index < vm.otp.count else { return nil }
        return vm.otp[vm.otp.index(vm.otp.startIndex, offsetBy: index)]
    }

    @ViewBuilder
    private var errorOrSpacer: some View {
        if vm.hasError {
            HStack(spacing: 6) {
                Text("✕")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColor.error)
                Text(vm.errorMsg)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColor.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppColor.errorSoft)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Color.clear.frame(height: 36)
        }
    }

    private var confirmButton: some View {
        let isEnabled = vm.otp.count == OtpViewModel.otpLength && !vm.isVerifying
        return Button(action: submit) {
            HStack(spacing: 8) {
                Text(vm.isVerifying ? "Đang xác thực..." : "Xác nhận")
                    .font(.system(size: 16, weight: .semibold))
                if !vm.isVerifying {
                    Text("✓").font(.system(size: 18, weight: .bold))
                }
            }
            .foregroundStyle(isEnabled ? .white : AppColor.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(isEnabled ? AppColor.brand : AppColor.bgSoft)
            .clipShape(RoundedRectangle(cornerRadius: 999, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var resendRow: some View {
        HStack(spacing: 6) {
            Text("Không nhận được mã?")
                .font(.system(size: 13))
                .foregroundStyle(AppColor.muted)

            if vm.canResend {
                Button(vm.isResending ? "Đang gửi..." : "Gửi lại OTP") {
                    Task { await vm.resend() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(vm.isResending ? AppColor.muted : AppColor.brand)
                .underline()
                .disabled(vm.isResending)
            } else {
                HStack(spacing: 0) {
                    Text("Gửi lại sau ")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColor.muted)
                    Text("\(vm.countdown)s")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColor.brand)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var maskedPhone: String {
        phone.count < 7 ? phone : "\(phone.prefix(3)) **** \(phone.suffix(3))"
    }

    private func submit() {
        Task {
            let ok = await vm.verify(phone: phone)
            if ok {
                onVerified()
            } else {
                await shake()
                try? await Task.sleep(nanoseconds: 150_000_000)
                isFocused = true
            }
        }
    }

    private func shake() async {
        let steps: [(CGFloat, Double)] = [(12, 0.06), (-12, 0.06), (8, 0.055), (-8, 0.055), (0, 0.05)]
        for (offset, duration) in steps {
            withAnimation(.linear(duration: duration)) {
                shakeOffset = offset
            }
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        }
    }
}

/// Step bar riêng của màn OTP — 3 vạch phẳng, KHÁC `ui/components/StepBar.kt`
/// (Android cũng dùng bản riêng `OtpStepBar`, không phải StepBar dùng chung).
private struct OtpStepBar: View {
    let step: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                // `step` đếm từ 1 (bước 1/3) còn `index` đếm từ 0 — phải là `<` chứ không
                // phải `<=`, nếu không bước 1 sẽ tô sáng 2 vạch. Kotlin lặp `1..3` nên
                // dùng `<=`; port sang đây đổi gốc lặp mà quên đổi phép so sánh.
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(index < step ? AppColor.brand : AppColor.muted.opacity(0.25))
                    .frame(height: 4)
            }
        }
    }
}

#Preview {
    OtpView(phone: "0387600501", onBack: {}, onVerified: {})
}
