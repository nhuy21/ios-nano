//
//  TransactionStore.swift
//  nano ewallet
//
//  Mirror phần "trang đầu" của TransactionRepository.kt — đủ cho Home hiển thị
//  giao dịch gần đây. Phần load-more/search đầy đủ thuộc HistoryScreen, làm ở
//  phase sau khi port History.
//
//  Android còn cache 5 giao dịch gần nhất vào SharedPreferences để Home hiện được
//  ngay cả khi offline — chưa cần thiết ở bước này vì Home chỉ cần "gọi API 1 lần
//  lúc vào màn"; bổ sung persist sau nếu cần trải nghiệm offline-first đầy đủ.
//

import Foundation
import Combine

@MainActor
final class TransactionStore: ObservableObject {

    static let shared = TransactionStore()
    private init() {}

    @Published private(set) var recentTransactions: [TransactionEntity] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?

    /// Nạp trang đầu (mặc định 5 giao dịch gần nhất cho Home).
    func refreshRecent(limit: Int = 5) async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let page = try await TransactionService.list(TransactionQuery(limit: limit))
            recentTransactions = page.items
        } catch {
            loadError = (error as? APIError)?.message ?? "Không tải được giao dịch"
        }
    }

    /// Thêm 1 giao dịch mới vào đầu danh sách — dùng khi vừa chuyển tiền xong hoặc
    /// nhận push realtime, không cần gọi lại API. Dedupe theo `id`.
    /// Khử trùng theo CẢ `id` LẪN `bkTransId`: bản ghi chèn sớm ngay sau khi chuyển tiền chỉ
    /// biết mã Bảo Kim (chưa có id nội bộ DB), còn bản từ push/API lại có id DB — chỉ so `id`
    /// thì một giao dịch hiện thành hai dòng.
    func prepend(_ transaction: TransactionEntity) {
        recentTransactions.removeAll {
            if $0.id == transaction.id { return true }
            guard let incoming = transaction.bkTransId, !incoming.isEmpty else { return false }
            return $0.bkTransId == incoming
        }
        recentTransactions.insert(transaction, at: 0)
    }

    func clear() {
        recentTransactions = []
        loadError = nil
    }
}
