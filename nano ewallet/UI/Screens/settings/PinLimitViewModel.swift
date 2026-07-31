//
//  PinLimitViewModel.swift
//  nano ewallet
//
//  Mirror phần state của PinLimitScreen.kt.
//

import Foundation
import Combine

@MainActor
final class PinLimitViewModel: ObservableObject {

    static let step = 1_000
    static let presets = [0, 100_000, 200_000, 300_000, 400_000, 500_000]

    @Published var selected: Int
    @Published var otp = ""
    @Published var otpMode = false
    @Published var isLoading = false
    @Published var error: String?

    let currentLimit: Int

    init() {
        let current = Int(WalletStore.shared.limitPin ?? WalletStore.defaultLimitPin)
        currentLimit = current
        selected = current
    }

    var hasChanged: Bool { selected != currentLimit }
    var canSave: Bool { hasChanged && !isLoading }
    var canConfirmOtp: Bool { otp.count == 6 && !isLoading }

    /// Bước 1: gửi OTP rồi chuyển sang otpMode.
    func sendOtp() async {
        guard canSave else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            try await AccountService.requestLimitPinOtp()
            otpMode = true
        } catch {
            self.error = (error as? APIError)?.message ?? "Không gửi được mã OTP, vui lòng thử lại"
        }
    }

    /// Bước 2: xác nhận ngưỡng mới.
    func confirm() async -> Bool {
        guard canConfirmOtp else { return false }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            try await AccountService.updateLimitPin(newLimit: selected, otp: otp)
            await WalletStore.shared.refresh(force: true)
            return true
        } catch {
            self.error = (error as? APIError)?.message ?? "Xác nhận thất bại, vui lòng thử lại"
            return false
        }
    }

    func resendOtp() async {
        otp = ""
        error = nil
        await sendOtp()
    }
}
