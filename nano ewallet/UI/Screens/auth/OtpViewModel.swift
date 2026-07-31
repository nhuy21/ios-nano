//
//  OtpViewModel.swift
//  nano ewallet
//
//  Mirror phần state của OtpScreen.kt.
//

import Foundation

@MainActor
final class OtpViewModel: ObservableObject {

    static let resendSeconds = 5 * 60
    static let otpLength = 6

    @Published var otp = "" {
        didSet {
            if otp.count > oldValue.count { errorMsg = "" }
            let filtered = String(otp.filter(\.isNumber).prefix(Self.otpLength))
            if filtered != otp { otp = filtered }
        }
    }
    @Published var errorMsg = ""
    @Published var countdown = 0
    @Published var canResend = true
    @Published var isVerifying = false
    @Published var isResending = false

    var hasError: Bool { !errorMsg.isEmpty }

    private var countdownTask: Task<Void, Never>?

    /// Trả true nếu verify thành công (dùng để View gọi onVerified và dừng shake).
    func verify(phone: String) async -> Bool {
        guard otp.count == Self.otpLength, !isVerifying else { return false }
        isVerifying = true
        defer { isVerifying = false }

        do {
            let outcome = try await AuthService.verifyOtp(otp)
            switch outcome {
            case .authenticated:
                return true
            case .requireDeviceOtp:
                // Tài khoản vừa verify OTP nhưng đang đăng nhập ở máy khác —
                // đẩy về Login để chạy lại luồng device-otp qua đó (hiếm gặp).
                errorMsg = "Tài khoản đang đăng nhập ở thiết bị khác, vui lòng đăng nhập lại"
                otp = ""
                return false
            case .requireOtp:
                errorMsg = "Mã OTP không đúng. Vui lòng kiểm tra lại."
                otp = ""
                return false
            }
        } catch {
            errorMsg = (error as? APIError)?.message ?? "Mã OTP không đúng. Vui lòng kiểm tra lại."
            otp = ""
            return false
        }
    }

    func resend() async {
        guard !isResending else { return }
        isResending = true
        defer { isResending = false }
        do {
            try await AuthService.resendOtp()
            startCountdown()
            otp = ""
            errorMsg = ""
        } catch {
            errorMsg = (error as? APIError)?.message ?? "Gửi lại OTP thất bại, vui lòng thử lại"
        }
    }

    func startCountdown() {
        countdown = Self.resendSeconds
        canResend = false
        countdownTask?.cancel()
        countdownTask = Task {
            while countdown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                countdown -= 1
            }
            canResend = true
        }
    }

    deinit {
        countdownTask?.cancel()
    }
}
