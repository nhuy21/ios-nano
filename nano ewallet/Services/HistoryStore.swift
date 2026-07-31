//
//  HistoryStore.swift
//  nano ewallet
//
//  Mirror phần phân trang/search của HistoryScreen.kt (qua TransactionRepository).
//  Tách riêng khỏi TransactionStore (dùng cho Home "5 giao dịch gần nhất") vì
//  History cần state phức tạp hơn: filter tab, search debounce, date range, cursor.
//
//  Cursor phân trang = `createdAt` (ISO-8601) của item cuối cùng, KHÔNG phải
//  offset/page number — đúng contract BE `GET transactions?before=`.
//

import Foundation
import Combine

enum HistoryFilter: Int, CaseIterable {
    case all = 0
    case income = 1
    case expense = 2

    var label: String {
        switch self {
        case .all: return "Tất cả"
        case .income: return "Nhận"
        case .expense: return "Chuyển"
        }
    }

    /// Param `type` gửi BE.
    var apiType: String {
        switch self {
        case .all: return "ALL"
        case .income: return "IN"
        case .expense: return "OUT"
        }
    }
}

@MainActor
final class HistoryStore: ObservableObject {

    static let pageSize = 50

    @Published private(set) var items: [TransactionEntity] = []
    @Published private(set) var isLoadingFirstPage = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var noMoreData = false
    @Published private(set) var loadError: String?

    @Published private(set) var isSearching = false
    @Published private(set) var searchError: String?

    private var isSearchResult = false

    /// Chế độ thường: gọi lại `loadFirstPage` khi đổi tab. Chế độ search: chỉ 1 trang.
    func loadFirstPage(filter: HistoryFilter) async {
        isLoadingFirstPage = true
        loadError = nil
        noMoreData = false
        isSearchResult = false
        defer { isLoadingFirstPage = false }
        do {
            let page = try await TransactionService.list(
                TransactionQuery(limit: Self.pageSize, type: filter.apiType)
            )
            items = page.items
            noMoreData = !page.hasMore
        } catch {
            loadError = (error as? APIError)?.message ?? "Úi! Mất kết nối rồi!"
        }
    }

    /// Cuộn gần đáy → nạp thêm trang tiếp theo. Không gọi khi đang ở kết quả search.
    func loadMore(filter: HistoryFilter) async {
        guard !isLoadingMore, !noMoreData, !isSearchResult, let last = items.last else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await TransactionService.list(
                TransactionQuery(limit: Self.pageSize, type: filter.apiType, before: last.createdAt)
            )
            items.append(contentsOf: page.items)
            noMoreData = !page.hasMore
        } catch {
            // Lỗi loadMore: giữ nguyên danh sách hiện có, chỉ đơn giản không nạp thêm được
            // lần này — user cuộn tiếp sẽ tự thử lại.
        }
    }

    /// Search 1 trang duy nhất (limit 100), không phân trang cuộn thêm.
    func search(filter: HistoryFilter, query: String, dateFrom: Date?, dateTo: Date?) async {
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            let page = try await TransactionService.list(
                TransactionQuery(
                    limit: 100,
                    type: filter.apiType,
                    q: query.isEmpty ? nil : query,
                    dateFrom: dateFrom.map(Self.startOfDayISO),
                    dateTo: dateTo.map(Self.endOfDayISO)
                )
            )
            items = page.items
            isSearchResult = true
            noMoreData = true
        } catch {
            searchError = (error as? APIError)?.message ?? "Không tìm kiếm được, vui lòng thử lại"
        }
    }

    private static func startOfDayISO(_ date: Date) -> String {
        let start = Calendar.current.startOfDay(for: date)
        return ISO8601DateFormatter.withFractionalSeconds.string(from: start)
    }

    private static func endOfDayISO(_ date: Date) -> String {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = 23
        components.minute = 59
        components.second = 59
        let end = Calendar.current.date(from: components) ?? date
        return ISO8601DateFormatter.withFractionalSeconds.string(from: end)
    }
}
