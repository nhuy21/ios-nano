//
//  QuickTransferIntent.swift
//  nano ewallet
//
//  "Hey Siri, chuyển 5 nghìn cho A trên Nano Wallet" — xem docs/siri-quick-transfer.md.
//
//  LƯU Ý BUILD: viết không có SDK AppIntents để compile-check tại chỗ (máy dev hiện tại
//  không cài Xcode) — kiểm lại kỹ khi build lần đầu trên máy có Xcode.
//

import AppIntents
import LocalAuthentication

enum QuickTransferError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case overLimit
    case needsAppConfirmation
    case biometricNotEnabled
    case biometricFailed
    case transferFailed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .overLimit:
            return "Số tiền vượt hạn mức \(Int(TransferLimits.faceFixed).vndFormatted), không thể chuyển bằng cách nào."
        case .needsAppConfirmation:
            return "Số tiền này cần xác nhận trong ứng dụng. Mở Ví nano để hoàn tất."
        case .biometricNotEnabled:
            return "Bạn cần bật xác thực Face ID cho giao dịch trong mục Cá nhân > Bảo mật trước khi dùng trợ lý giọng nói."
        case .biometricFailed:
            return "Không xác thực được Face ID, giao dịch đã huỷ."
        case .transferFailed(let message):
            return "\(message)"
        }
    }
}

/// Intent chính, expose ra Siri qua `QuickTransferShortcuts` — LUÔN chạy ngầm
/// (`openAppWhenRun` mặc định `false`, KHÔNG khai lại ở đây). Tuỳ số tiền, hoặc chuyển ngay
/// sau khi quét mặt (tầng 1), hoặc đặt cờ để người dùng xác nhận trong app (tầng 2).
struct QuickTransferIntent: AppIntent {
    static var title: LocalizedStringResource = "Chuyển tiền"
    static var description = IntentDescription("Chuyển tiền cho một người trong danh bạ ví.")

    @Parameter(title: "Người nhận") var recipient: WalletContactEntity
    @Parameter(title: "Số tiền") var amount: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Chuyển \(\.$amount) cho \(\.$recipient)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let amountValue = Int64(amount)

        // Tầng 3: vượt limitFace — không chuyển được bằng cách nào, dừng ngay trước khi
        // đụng tới bất cứ thứ gì khác (không cần biết đã bật sinh trắc hay chưa).
        guard amountValue <= TransferLimits.faceFixed else {
            throw QuickTransferError.overLimit
        }

        let limitPin = WalletStore.shared.limitPin ?? WalletStore.defaultLimitPin

        // Tầng 2: giữa limitPin và limitFace — số tiền này BẮT BUỘC xác nhận trong app.
        //
        // KHÔNG dùng `.result(opensIntent:)`: overload đó trả `IntentResultContainer` với
        // `Dialog == Never`, không cùng kiểu với `.result(dialog:)` ở nhánh tầng 1, mà kiểu trả
        // về `some ...` là opaque nên buộc mọi nhánh `return` phải cùng một kiểu cụ thể.
        //
        // Thay vào đó: đặt cờ vào `DeepLinkStore` rồi `throw` kèm thông báo. `MainTabView` tiêu
        // thụ cờ và đẩy vào `Route.walletTransferAmount` ngay khi người dùng mở app — đúng
        // pattern `pendingWalletTransferShortcut` đã dùng cho Quick Action.
        guard amountValue <= limitPin else {
            DeepLinkStore.shared.requestQuickTransfer(
                draft: WalletTransferDraft(
                    username: recipient.benUsername,
                    holderName: recipient.name,
                    prefillAmount: amountValue
                )
            )
            throw QuickTransferError.needsAppConfirmation
        }

        // Tầng 1: dưới limitPin.
        //
        // QUYẾT ĐỊNH QUAN TRỌNG (khác bản nháp đầu của doc thiết kế): amount < limitPin thì
        // BE (`wallet.service.ts` executeTransferToWallet) THỰC THI NGAY, không tạo pending,
        // nên KHÔNG có transactionId nào để gọi `verify-transfer-biometric` — endpoint đó chỉ
        // dùng được khi có giao dịch pending. Vì vậy Face ID ở tầng này KHÔNG ký gì, KHÔNG
        // gọi BiometricService — nó là lớp CHẶN PHÍA CLIENT trước khi gọi thẳng
        // transferToWallet, đúng cách UI app hiện tại xử lý giao dịch dưới limitPin (không
        // hiện PinEntrySheet/BiometricAuthSheet, chuyển thẳng).
        guard BiometricKeyStore.hasKey() else {
            throw QuickTransferError.biometricNotEnabled
        }

        // Hộp thoại Face ID CHÍNH LÀ bước xác nhận: `localizedReason` hiện đúng số tiền và tên
        // người nhận, người dùng nhìn thấy trước khi quét mặt. Không gọi thêm
        // `requestConfirmation` — hỏi hai lần cho cùng một giao dịch là dư thừa.
        guard await Self.authenticate(reason: "Chuyển \(amount)đ cho \(recipient.name)?") else {
            throw QuickTransferError.biometricFailed
        }

        let result: TransferResult
        do {
            let request = TransferToWalletRequest(
                idempotencyKey: UUID().uuidString,
                benUsername: recipient.benUsername,
                accName: recipient.name,
                transAmount: amount,
                memo: "Chuyển tiền qua ví Nano"
            )
            result = try await TransferService.transferToWallet(request)
        } catch let error as APIError {
            throw QuickTransferError.transferFailed(error.message)
        } catch {
            throw QuickTransferError.transferFailed("Chuyển tiền thất bại, vui lòng thử lại trong app")
        }

        // `limitPin` đọc lúc nãy có thể đã CŨ (user hạ ngưỡng ở máy khác giữa lúc nói câu
        // lệnh và lúc Siri thực sự chạy perform()) — BE là nơi quyết định cuối cùng, không
        // phải giá trị client đã kiểm tra. BE trả pending thì KHÔNG được báo "đã chuyển":
        // tiền chưa đi, và ngữ cảnh Siri không có UI để nhập PIN/Face ID xác thực tiếp.
        guard !result.isPending else {
            throw QuickTransferError.transferFailed(
                "Giao dịch cần xác thực thêm, vui lòng mở app để hoàn tất"
            )
        }

        return .result(dialog: "Đã chuyển \(amount)đ cho \(recipient.name)")
    }

    /// Bọc thủ công bằng `withCheckedContinuation` thay vì tin vào async overload tự sinh của
    /// compiler cho `evaluatePolicy(_:localizedReason:reply:)` — API này vốn completion-handler
    /// based, không có `async throws` native trong `LocalAuthentication`. Cách này chắc chắn
    /// đúng bất kể SDK có tự sinh wrapper hay không.
    private static func authenticate(reason: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let context = LAContext()
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            ) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}

/// CHỈ đăng ký shortcut từ iOS 18.4 — mốc Apple thêm tiếng Việt cho Siri.
///
/// `phrases` bên dưới là tiếng Việt, nên trên máy 16-18.3 Siri không bao giờ khớp được. Để
/// shortcut xuất hiện trong app Shortcuts ở những bản đó chỉ gây rối: người dùng thấy mục
/// "Chuyển tiền nhanh" nhưng ra lệnh bằng giọng nói thì Siri báo không hiểu.
///
/// Đánh dấu ở CẤP TYPE (không phải cấp property `appShortcuts`): hệ thống quét
/// `AppShortcutsProvider` lúc cài app để đăng ký metadata, `@available` ở type là cách duy nhất
/// khiến nó bỏ qua hẳn trên máy chưa đủ phiên bản.
///
/// KHÔNG bọc `QuickTransferIntent` (vẫn iOS 16+): người dùng vẫn tự tạo được shortcut cho nó
/// trong app Shortcuts và chạy bằng tay — chỉ phần Siri đọc `phrases` mới cần 18.4.
@available(iOS 18.4, *)
struct QuickTransferShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickTransferIntent(),
            phrases: [
                "Chuyển \(.applicationName) cho \(\.$recipient)",
                "Chuyển tiền cho \(\.$recipient) trên \(.applicationName)",
            ],
            shortTitle: "Chuyển tiền nhanh",
            systemImageName: "paperplane.fill"
        )
    }
}
