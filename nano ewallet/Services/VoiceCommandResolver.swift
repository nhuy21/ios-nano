//
//  VoiceCommandResolver.swift
//  nano ewallet
//
//  Bóc "chuyển 200 nghìn cho Mẹ" thành người nhận + số tiền — mirror
//  `matchWalletRecipient` + `voiceAmount` trong VoiceCommandOverlay.kt.
//
//  KHÔNG tự chuyển tiền: chỉ điền sẵn rồi đưa sang màn nhập tiền, người dùng vẫn
//  phải xác nhận và nhập PIN.
//

import Foundation

enum VoiceCommandResult {
    case wallet(WalletTransferDraft)
    case failure(String)
}

enum VoiceCommandResolver {

    /// Khớp người nhận theo TÊN trong danh bạ ví. Chỉ danh bạ, giống bản Android —
    /// không dò số tài khoản đọc thành chữ số, vì recognizer nghe nhầm một chữ số là
    /// ra người khác mà tên hiển thị vẫn trông hợp lệ.
    static func resolve(
        candidates: [String],
        contacts: [Beneficiary]
    ) -> VoiceCommandResult {
        guard !candidates.isEmpty else {
            return .failure("Chưa nghe được gì. Thử nói lại xem.")
        }

        guard let match = matchWalletRecipient(candidates: candidates, contacts: contacts),
              let username = match.benUsername, !username.isEmpty else {
            return .failure(
                "Chưa nhận ra người nhận trong danh bạ ví. Thử nói: \"chuyển 200 nghìn cho Mẹ\"."
            )
        }

        return .wallet(
            WalletTransferDraft(
                username: username,
                holderName: match.accName ?? match.displayName,
                prefillAmount: voiceAmount(from: candidates)
            )
        )
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

    /// Khớp người nhận theo TỪ (không phải chuỗi con) nên không nhầm "mẹ" với "mến".
    /// So cả nickname LẪN từng từ của accName: nói "Đức" khớp contact tên "Nguyen Van Duc"
    /// dù chưa đặt nickname. Chọn contact có từ khớp DÀI nhất — tên riêng ("duc") thắng
    /// họ/đệm chung ("van", "nguyen").
    static func matchWalletRecipient(
        candidates: [String],
        contacts: [Beneficiary]
    ) -> Beneficiary? {
        let spoken = Set(candidates.flatMap(words))
        guard !spoken.isEmpty else { return nil }

        var best: Beneficiary?
        var bestScore = 0
        for contact in contacts {
            let nameTokens = [contact.nickname, contact.accName]
                .compactMap { $0 }
                .flatMap(words)
            let score = nameTokens.filter(spoken.contains).map(\.count).max() ?? 0
            if score > bestScore {
                bestScore = score
                best = contact
            }
        }
        return best
    }

    // MARK: - Private

    /// Bỏ dấu + hạ chữ thường, tách thành từ, bỏ từ quá ngắn (<2) để đỡ nhiễu.
    private static func words(_ text: String) -> [String] {
        text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 2 }
    }
}
