//
//  TransferLimits.swift
//  nano ewallet
//

import Foundation

/// Hạn mức giao dịch dùng chung toàn app — gộp về 1 nơi để không lặp lại hardcode độc lập
/// (bài học từ Quick Action: 2 chuỗi type tách rời không ai canh khớp, xem
/// `docs/siri-quick-transfer.md` mục 7).
enum TransferLimits {
    /// Hạn mức 1 lần rút/chuyển tối đa, CỐ ĐỊNH cho mọi user — khớp `wallets.limitFace`
    /// mặc định phía BE (Bảo Kim từ chối thẳng nếu vượt, mã lỗi 128). Khác `limitPin`
    /// (`WalletStore.shared.limitPin`), hạn mức này KHÔNG kéo theo từng user từ DB.
    static let faceFixed: Int64 = 10_000_000

    /// Số chips gợi ý số tiền hiện cùng lúc.
    static let suggestionCount = 3
    /// Gợi ý luôn từ hàng nghìn trở lên — đề xuất vài trăm đồng là vô nghĩa.
    static let minSuggestion: Int64 = 1_000

    /// Gợi ý số tiền theo số ĐANG GÕ: nhân 10 dần, mỗi mức gấp 10 lần mức trước.
    ///
    /// Mức ĐẦU TIÊN phải đạt tối thiểu 1.000 — nhân 10 mà chưa đủ thì nhân tiếp cho tới khi
    /// đủ, rồi các mức sau cứ ×10 mức trước:
    /// - gõ "1000" -> 10.000 / 100.000 / 1.000.000 / 10.000.000
    /// - gõ "5"    -> ×10 = 50 và ×100 = 500 đều chưa đủ 1.000, nên bắt đầu từ 5.000, thành
    ///                5.000 / 50.000 / 500.000 / 5.000.000
    ///
    /// - Parameters:
    ///   - minimum: sàn của màn gọi, mặc định `minSuggestion`. Màn chuyển khoản có mức tối
    ///     thiểu riêng nên truyền vào — gợi ý một số rồi tự chặn thì nhìn như app lỗi.
    ///   - maximum: trần của màn gọi (hạn mức 1 lần). Mức vượt trần bị bỏ, cùng lý do trên.
    static func amountSuggestions(
        for typed: Int64,
        min minimum: Int64 = minSuggestion,
        max maximum: Int64 = faceFixed
    ) -> [Int64] {
        guard typed > 0 else { return [] }

        var first = typed * 10
        // Trần 12 vòng: đủ để leo từ 1 lên hàng nghìn tỷ, và chặn lặp vô hạn nếu số vào quá
        // lớn khiến phép nhân tràn.
        var steps = 0
        while first < minSuggestion, steps < 12 {
            first *= 10
            steps += 1
        }

        var result: [Int64] = []
        var value = first
        for _ in 0..<suggestionCount {
            guard value <= maximum else { break }
            if value >= minimum { result.append(value) }
            value *= 10
        }
        return result
    }
}
