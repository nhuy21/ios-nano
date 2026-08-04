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
}
