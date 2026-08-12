//
//  VoiceCommandResolver.swift
//  nano ewallet
//
//  Bóc "chuyển 200 nghìn cho Mẹ" thành người nhận + số tiền — mirror
//  `matchRecipient` + `voiceAmount` trong VoiceCommandOverlay.kt.
//
//  KHÔNG tự chuyển tiền: chỉ điền sẵn rồi đưa sang màn nhập tiền, người dùng vẫn
//  phải xác nhận và nhập PIN.
//

import Foundation

enum VoiceCommandResult {
    case wallet(WalletTransferDraft)
    case bank(BankTransferDraft)
    case failure(String)
}

enum VoiceCommandResolver {

    /// Khớp người nhận theo TÊN trong danh bạ (cả ví lẫn ngân hàng). Chỉ danh bạ, giống bản
    /// Android — không dò số tài khoản đọc thành chữ số, vì recognizer nghe nhầm một chữ số
    /// là ra người khác mà tên hiển thị vẫn trông hợp lệ.
    ///
    /// - Parameter bankName: tra tên ngân hàng theo BIN (`BankCache`) — resolver không tự
    ///   đụng cache được vì nó `nonisolated`, để nơi gọi truyền vào.
    static func resolve(
        candidates: [String],
        contacts: [Beneficiary],
        bankName: (String?) -> String = { _ in "Ngân hàng" }
    ) -> VoiceCommandResult {
        guard !candidates.isEmpty else {
            return .failure("Chưa nghe được gì. Thử nói lại xem.")
        }

        guard let match = matchRecipient(candidates: candidates, contacts: contacts) else {
            return .failure(
                "Chưa nhận ra người nhận trong danh bạ. Thử nói: \"chuyển 200 nghìn cho Mẹ\"."
            )
        }

        let amount = voiceAmount(from: candidates)
        switch match.type {
        case .wallet:
            guard let username = match.benUsername, !username.isEmpty else {
                return .failure("Người nhận này thiếu số ví, thử chọn từ danh bạ.")
            }
            return .wallet(
                WalletTransferDraft(
                    username: username,
                    holderName: match.accName ?? match.displayName,
                    prefillAmount: amount
                )
            )
        case .bankAccount:
            guard let accNo = match.accNo, !accNo.isEmpty else {
                return .failure("Người nhận này thiếu số tài khoản, thử chọn từ danh bạ.")
            }
            return .bank(
                BankTransferDraft(
                    bin: match.bankNo ?? "",
                    bankName: bankName(match.bankNo),
                    accNo: accNo,
                    accType: 0,
                    holderName: match.accName ?? match.displayName,
                    // `BankTransferDraft.prefillAmount` là `Int?`, khác `Int64?` bên ví.
                    prefillAmount: amount.map(Int.init)
                )
            )
        }
    }

    /// Số tiền từ câu NÓI. Quy ước riêng của lời nói: số trơn NHỎ (<1000) hiểu là
    /// NGHÌN — "chuyển 150 cho Đức" = 150.000đ, trừ khi nói rõ "đồng".
    static func voiceAmount(from candidates: [String]) -> Int64? {
        guard let amount = SpeechAmountParser.pickAmount(from: candidates) else { return nil }
        let saidDong = candidates.contains { text in
            let lowered = text.lowercased()
            return lowered.contains("đồng")
                || lowered.range(of: #"\d\s*đ\b"#, options: .regularExpression) != nil
        }
        return (amount < 1_000 && !saidDong) ? amount * 1_000 : amount
    }

    /// Điểm cộng cho contact khớp TÊN GỢI NHỚ. Đặt lớn hơn mọi độ dài từ có thể gặp để ưu
    /// tiên là tuyệt đối — tên người Việt không có từ nào dài tới 1000 ký tự.
    nonisolated private static let nicknameBonus = 1000

    /// Khớp người nhận theo TỪ (không phải chuỗi con) nên không nhầm "mẹ" với "mến".
    /// So cả tên gợi nhớ LẪN từng từ của tên thật: nói "Đức" khớp contact tên
    /// "Nguyen Van Duc" dù chưa đặt tên gợi nhớ.
    ///
    /// TÊN GỢI NHỚ ĐƯỢC ƯU TIÊN TUYỆT ĐỐI: người dùng tự đặt nó chính là để gọi, nên khớp
    /// vào đó luôn thắng mọi contact chỉ khớp tên thật — kể cả khi tên thật khớp một từ dài
    /// hơn. Nói "Mẹ" phải ra contact đặt tên gợi nhớ "Mẹ", không ra người tên
    /// "Nguyen Thi Me".
    ///
    /// Trong cùng một hạng thì chọn từ khớp DÀI nhất — tên riêng ("duc") thắng họ/đệm chung
    /// ("van", "nguyen").
    nonisolated static func matchRecipient(
        candidates: [String],
        contacts: [Beneficiary]
    ) -> Beneficiary? {
        let spoken = Set(candidates.flatMap(words))
        guard !spoken.isEmpty else { return nil }

        /// 0 = không khớp. Khớp tên gợi nhớ được cộng `nicknameBonus` nên LUÔN đứng trên mọi
        /// contact chỉ khớp tên thật, bất kể từ khớp bên kia dài bao nhiêu; phần dư bên dưới
        /// vẫn là độ dài từ khớp nên trong cùng hạng thì tên riêng ("duc") thắng họ đệm
        /// ("van", "nguyen").
        ///
        /// Gộp vào MỘT số thay vì tuple `(Bool, Int)`: Swift không cấp `<`/`>` cho tuple
        /// (chỉ có `==`), viết `current > bestScore` là lỗi biên dịch.
        func score(_ contact: Beneficiary) -> Int {
            func longestMatch(_ value: String?) -> Int {
                guard let value else { return 0 }
                return words(value).filter(spoken.contains).map(\.count).max() ?? 0
            }
            let byNickname = longestMatch(contact.nickname)
            let best = max(byNickname, longestMatch(contact.accName))
            guard best > 0 else { return 0 }
            return best + (byNickname > 0 ? nicknameBonus : 0)
        }

        var best: Beneficiary?
        var bestScore = 0
        for contact in contacts {
            let current = score(contact)
            // Bỏ qua contact không khớp từ nào — không chặn thì nói một câu vu vơ vẫn ra
            // người nhận đầu danh sách.
            guard current > bestScore else { continue }
            bestScore = current
            best = contact
        }
        return best
    }

    // MARK: - Private

    /// Bỏ dấu + hạ chữ thường, tách thành từ, bỏ từ quá ngắn (<2) để đỡ nhiễu.
    ///
    /// `nonisolated` vì project bật `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: hàm này
    /// được truyền làm GIÁ TRỊ vào `flatMap(words)` (context nonisolated), nếu để suy ra
    /// `@MainActor` thì không truyền được.
    nonisolated private static func words(_ text: String) -> [String] {
        text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 2 }
    }
}
