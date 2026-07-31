//
//  WalletStore.swift
//  nano ewallet
//
//  Mirror WalletCache.kt — cache 2 tầng: UserDefaults (đĩa, hiện ngay lúc mở app kể cả
//  offline) + @Published (memory, HomeView tự cập nhật khi refresh hoặc nhận push).
//
//  Chính sách: `refresh(force:)` — false thì bỏ qua nếu memory đã có; true (Home dùng)
//  luôn gọi API để số dư được revalidate. Lỗi mạng: GIỮ NGUYÊN cache cũ, chỉ hiện 0 khi
//  chưa từng có dữ liệu gì (lần đầu mở app mà mất mạng).
//

import Foundation
import Combine

@MainActor
final class WalletStore: ObservableObject {

    static let shared = WalletStore()

    static let defaultLimitPin: Int64 = 500_000

    @Published private(set) var bkUsername: String?
    @Published private(set) var qrPath: String?
    @Published private(set) var vaNumber: String?
    @Published private(set) var vaBankNo: String?
    @Published private(set) var balance: Int64?
    @Published private(set) var bankNo: String?
    @Published private(set) var accNo: String?
    @Published private(set) var accName: String?
    @Published private(set) var limitPin: Int64?
    @Published private(set) var bankLinkedAt: String?

    private var isLoading = false

    private init() {
        load()
    }

    /// Gọi API lấy bản mới nhất, ghi đè cả memory lẫn đĩa.
    /// - Parameter force: false = bỏ qua nếu memory đã có (đủ dữ liệu là thôi);
    ///   true = luôn gọi — Home dùng cái này để số dư luôn được revalidate.
    func refresh(force: Bool = false) async {
        if isLoading { return }
        if !force && balance != nil { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let wallet = try await WalletService.getMyWallet()
            bkUsername = wallet.bkUsername
            qrPath = wallet.qrPath
            vaNumber = wallet.vaNumber
            vaBankNo = wallet.vaBankNo
            balance = wallet.balance ?? 0
            bankNo = wallet.bankNo
            accNo = wallet.accNo
            accName = wallet.accName
            limitPin = wallet.limitPinAmount ?? Self.defaultLimitPin
            bankLinkedAt = wallet.bankLinkedAt
            persist()
        } catch {
            // Lỗi mạng: giữ nguyên cache đang có. Chưa từng có gì (lần đầu mở app mất
            // mạng) thì hiện 0 thay vì "..." mãi.
            if balance == nil { balance = 0 }
        }
    }

    /// Set thẳng số dư từ payload push realtime — không gọi mạng.
    func setBalance(_ value: Int64) {
        balance = value
        persist()
    }

    /// Gọi khi logout — xoá cả memory lẫn đĩa, không để dữ liệu user cũ lộ ra.
    func clear() {
        bkUsername = nil
        qrPath = nil
        vaNumber = nil
        vaBankNo = nil
        balance = nil
        bankNo = nil
        accNo = nil
        accName = nil
        limitPin = nil
        bankLinkedAt = nil
        Key.allCases.forEach { UserDefaults.standard.removeObject(forKey: $0.rawValue) }
    }

    // MARK: - Persist

    private enum Key: String, CaseIterable {
        case bkUsername = "wallet_bk_username"
        case qrPath = "wallet_qr_path"
        case vaNumber = "wallet_va_number"
        case vaBankNo = "wallet_va_bank_no"
        case balance = "wallet_balance"
        case bankNo = "wallet_bank_no"
        case accNo = "wallet_acc_no"
        case accName = "wallet_acc_name"
        case limitPin = "wallet_limit_pin"
        case bankLinkedAt = "wallet_bank_linked_at"
    }

    private func load() {
        let d = UserDefaults.standard
        bkUsername = d.string(forKey: Key.bkUsername.rawValue)
        qrPath = d.string(forKey: Key.qrPath.rawValue)
        vaNumber = d.string(forKey: Key.vaNumber.rawValue)
        vaBankNo = d.string(forKey: Key.vaBankNo.rawValue)
        balance = d.object(forKey: Key.balance.rawValue) != nil ? Int64(d.integer(forKey: Key.balance.rawValue)) : nil
        bankNo = d.string(forKey: Key.bankNo.rawValue)
        accNo = d.string(forKey: Key.accNo.rawValue)
        accName = d.string(forKey: Key.accName.rawValue)
        limitPin = d.object(forKey: Key.limitPin.rawValue) != nil ? Int64(d.integer(forKey: Key.limitPin.rawValue)) : nil
        bankLinkedAt = d.string(forKey: Key.bankLinkedAt.rawValue)
    }

    private func persist() {
        let d = UserDefaults.standard
        setOrRemove(d, Key.bkUsername, bkUsername)
        setOrRemove(d, Key.qrPath, qrPath)
        setOrRemove(d, Key.vaNumber, vaNumber)
        setOrRemove(d, Key.vaBankNo, vaBankNo)
        if let balance { d.set(Int(balance), forKey: Key.balance.rawValue) } else { d.removeObject(forKey: Key.balance.rawValue) }
        setOrRemove(d, Key.bankNo, bankNo)
        setOrRemove(d, Key.accNo, accNo)
        setOrRemove(d, Key.accName, accName)
        if let limitPin { d.set(Int(limitPin), forKey: Key.limitPin.rawValue) } else { d.removeObject(forKey: Key.limitPin.rawValue) }
        setOrRemove(d, Key.bankLinkedAt, bankLinkedAt)
    }

    private func setOrRemove(_ d: UserDefaults, _ key: Key, _ value: String?) {
        if let value { d.set(value, forKey: key.rawValue) } else { d.removeObject(forKey: key.rawValue) }
    }
}
