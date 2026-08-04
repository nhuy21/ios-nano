//
//  HistoryView.swift
//  nano ewallet
//
//  Mirror HistoryScreen.kt — filter tab (Tất cả/Nhận/Chuyển), search + date range
//  (debounce 400ms), infinite scroll (cursor = createdAt item cuối), group theo ngày.
//

import SwiftUI
import Combine

/// Palette riêng của màn này — mirror các hằng private trong HistoryScreen.kt (L93-115).
/// Tên `AccentOrange` bên Kotlin gây nhầm: giá trị là XANH LÁ, không phải cam.
private enum HistoryColor {
    /// Nền TRẮNG — card phân biệt bằng shadow mỏng, không phải xám nhạt.
    static let screenBg = Color.white
    static let accent = Color(hex: 0x00A85E)
    static let activeTabBg = Color(hex: 0xE6F7EE)
    /// Viền viên thuốc filter (Tất cả/Nhận/Chuyển) — xanh rất đậm.
    static let pillBorder = Color(hex: 0x00542F)
    /// Tiền vào — đồng bộ với `HomeScreen.TxnRow`.
    static let greenPositive = Color(hex: 0x12A67E)
    /// Đường kẻ mảnh trong card.
    static let cardLine = Color(hex: 0xF0EAE6)
    /// Viền card + viền ô tìm kiếm.
    static let cardBorder = Color(hex: 0xEDEFF2)
}

struct HistoryView: View {
    let onBack: () -> Void

    @StateObject private var store = HistoryStore()

    @State private var filter: HistoryFilter = .all
    @State private var showSearch = false
    @State private var searchText = ""
    @State private var dateStart: Date?
    @State private var dateEnd: Date?
    @State private var showDateFilter = false
    @State private var detailTransaction: TransactionEntity?
    @State private var searchTask: Task<Void, Never>?

    private var isSearchMode: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty || dateStart != nil || dateEnd != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if showSearch {
                searchBar
            }

            if dateStart != nil || dateEnd != nil {
                dateChip
            }

            content
        }
        .background(HistoryColor.screenBg)
        .sheet(isPresented: $showDateFilter) {
            DateFilterSheet(
                dateStart: $dateStart,
                dateEnd: $dateEnd,
                onApply: { triggerSearchOrReload() },
                onDismiss: { showDateFilter = false }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $detailTransaction) { tx in
            TransactionDetailSheet(tx: tx, onDismiss: { detailTransaction = nil })
        }
        .task {
            await store.loadFirstPage(filter: filter)
        }
        .onChange(of: searchText) { _, _ in triggerSearchOrReload() }
    }

    // MARK: - Header

    /// Mirror HistoryScreen.kt L395-423: nút back TRẦN (không nền trắng + shadow như các màn
    /// Settings), title 20sp Bold, hai nút phải cách nhau 10.
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(AppColor.payInk)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quay lại")

                Text("Lịch sử giao dịch")
                    .font(AppFont.beVietnamPro(20, .bold))
                    .foregroundStyle(AppColor.payInk)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                headerIconButton(systemImage: "magnifyingglass", isActive: showSearch) {
                    showSearch.toggle()
                    if !showSearch {
                        searchText = ""
                        triggerSearchOrReload()
                    }
                }
                headerIconButton(systemImage: "calendar", isActive: dateStart != nil || dateEnd != nil) {
                    showDateFilter = true
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    /// Icon LUÔN tint accent (kể cả khi không active) — chỉ nền đổi. Mirror
    /// `HeaderIconButton` (HistoryScreen.kt L911-933).
    private func headerIconButton(systemImage: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .foregroundStyle(HistoryColor.accent)
                .frame(width: 40, height: 40)
                .background(isActive ? HistoryColor.activeTabBg : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search bar + date chip

    /// Mirror HistoryScreen.kt L426-474: cao 46, viền `#EDEFF2`, icon kính lúp tint ACCENT
    /// (không phải muted), nút xoá chỉ hiện khi có chữ.
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(HistoryColor.accent)
            TextField("Tìm theo tên, nội dung...", text: $searchText)
                .font(AppFont.beVietnamPro(14, .medium))
                .foregroundStyle(AppColor.payInk)
                .tint(HistoryColor.accent)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18))
                        .foregroundStyle(AppColor.payMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Xoá")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(HistoryColor.cardBorder, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0x14 / 255.0), radius: 6, x: 0, y: 2)
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private var dateChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 12))
            Text(rangeLabel)
                .font(AppFont.beVietnamPro(12, .medium))
            Button {
                dateStart = nil
                dateEnd = nil
                triggerSearchOrReload()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(AppColor.brand)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppColor.brandSoft)
        .clipShape(Capsule())
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var rangeLabel: String {
        let formatter = DateFormatter.app("dd/MM/yyyy")
        let shortFormatter = DateFormatter.app("dd/MM")

        switch (dateStart, dateEnd) {
        case (nil, nil):
            return "Mọi ngày"
        case let (start?, end?) where Calendar.app.isDate(start, inSameDayAs: end):
            return formatter.string(from: start)
        case let (start?, end?):
            return "\(shortFormatter.string(from: start)) – \(formatter.string(from: end))"
        case let (start?, nil):
            return "Từ \(formatter.string(from: start))"
        case let (nil, end?):
            return "Đến \(formatter.string(from: end))"
        }
    }

    // MARK: - Nội dung

    @ViewBuilder
    private var content: some View {
        if let error = store.loadError, store.items.isEmpty, !isSearchMode {
            fullScreenError(error)
        } else if store.isLoadingFirstPage && store.items.isEmpty {
            ProgressView().tint(AppColor.brand).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    filterTabs
                        .padding(.bottom, 20)

                    if isSearchMode && store.isSearching {
                        ProgressView().tint(AppColor.brand).padding(.top, 40)
                    } else if isSearchMode, let searchError = store.searchError {
                        Text(searchError)
                            .font(AppFont.beVietnamPro(13))
                            .foregroundStyle(AppColor.payMuted)
                            .padding(.top, 40)
                    } else if store.items.isEmpty {
                        emptyState
                    } else {
                        transactionGroups
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 24) }
        }
    }

    /// Ba viên thuốc RỜI (không segmented liền trong 1 capsule như bản trước) — mirror
    /// HistoryScreen.kt L525-558: active nền `#00542F` chữ trắng, inactive nền trắng chữ
    /// `#00542F`, cả hai đều có viền `#00542F`.
    private var filterTabs: some View {
        HStack(spacing: 10) {
            ForEach(HistoryFilter.allCases, id: \.self) { tab in
                let isActive = filter == tab
                Button {
                    filter = tab
                    triggerSearchOrReload()
                } label: {
                    Text(tab.label)
                        .font(AppFont.beVietnamPro(13, .semibold))
                        .foregroundStyle(isActive ? .white : HistoryColor.pillBorder)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background(isActive ? HistoryColor.pillBorder : Color.white)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().strokeBorder(HistoryColor.pillBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var transactionGroups: some View {
        let groups = groupedByDay(store.items)
        return VStack(spacing: 12) {
            ForEach(groups, id: \.label) { group in
                VStack(alignment: .leading, spacing: 0) {
                    // Nhãn ngày 13sp Medium (không SemiBold), padding top 4 / bottom 10.
                    Text(group.label)
                        .font(AppFont.beVietnamPro(13, .medium))
                        .foregroundStyle(AppColor.payMuted)
                        .padding(.top, 4)
                        .padding(.bottom, 10)

                    VStack(spacing: 0) {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, tx in
                            // Divider chạy HẾT bề rộng card (Kotlin không thụt lề trái).
                            if index > 0 {
                                Rectangle()
                                    .fill(HistoryColor.cardLine)
                                    .frame(height: 1)
                            }
                            row(tx)
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(HistoryColor.cardBorder, lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0x1A / 255.0), radius: 8, x: 0, y: 2)
                }
            }

            if store.isLoadingMore {
                ProgressView().tint(AppColor.brand).padding(.top, 12)
            } else if store.noMoreData && !isSearchMode {
                Text("Đã hiển thị toàn bộ giao dịch")
                    .font(AppFont.beVietnamPro(12))
                    .foregroundStyle(AppColor.payMuted)
                    .padding(.top, 12)
            } else if !isSearchMode {
                // Trigger vô hình gần đáy để load thêm khi cuộn tới.
                Color.clear.frame(height: 1)
                    .onAppear { Task { await store.loadMore(filter: filter) } }
            }
        }
    }

    /// Mirror `TxnRow` (HistoryScreen.kt:936-1005). Khác bản trước ở 4 điểm theo bản Kotlin
    /// mới: KHÔNG vẽ nền tròn pastel sau icon, glyph to 24 thay vì 16, canh TOP thay vì
    /// giữa, và tiền RA để màu mực đen (`payInk`) chứ không đỏ — chỉ tiền vào mới lên màu.
    private func row(_ tx: TransactionEntity) -> some View {
        let icon = TransactionDisplay.iconStyle(for: tx)
        return Button {
            detailTransaction = tx
        } label: {
            HStack(alignment: .top, spacing: 8) {
                TransactionIcon(kind: icon.icon, tint: icon.tint)
                    .frame(width: 24, height: 24)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 0) {
                    Text(TransactionDisplay.listTitle(for: tx))
                        .font(AppFont.beVietnamPro(14, .semibold))
                        .foregroundStyle(AppColor.payInk)
                        .lineSpacing(4)
                        .lineLimit(2)
                    Text(timeLabel(tx.createdAt))
                        .font(AppFont.beVietnamPro(12))
                        .foregroundStyle(AppColor.payMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Khoá bề rộng cột phải để cột tên luôn nhận tỉ lệ cố định -> số dòng ổn
                // định giữa các máy, không phụ thuộc độ dài chuỗi.
                VStack(alignment: .trailing, spacing: 0) {
                    Text(signedAmount(tx))
                        .font(AppFont.beVietnamPro(14, .bold))
                        .foregroundStyle(tx.isIncome ? HistoryColor.greenPositive : AppColor.payInk)
                        .lineLimit(1)
                    if let balance = tx.cachedBalanceAfterValue {
                        Text("Số dư: \(Int(balance).vndFormatted)")
                            .font(AppFont.beVietnamPro(11))
                            .foregroundStyle(AppColor.payMuted)
                            .lineLimit(1)
                    }
                }
                .frame(minWidth: 96, maxWidth: 132, alignment: .trailing)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty / error states

    private var emptyState: some View {
        VStack(spacing: 12) {
            Circle()
                .fill(AppColor.brandSoft)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(AppColor.brand)
                }

            Text(isSearchMode ? "Không tìm thấy giao dịch phù hợp" : "Chưa có giao dịch nào")
                .font(AppFont.beVietnamPro(15, .semibold))
                .foregroundStyle(AppColor.payInk)

            Text(isSearchMode ? "Thử đổi từ khoá hoặc khoảng ngày khác" : "Giao dịch của bạn sẽ hiển thị ở đây")
                .font(AppFont.beVietnamPro(13))
                .foregroundStyle(AppColor.payMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }

    private func fullScreenError(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text("Úi! Mất kết nối rồi!")
                .font(AppFont.beVietnamPro(17, .bold))
                .foregroundStyle(AppColor.payInk)
            Text("Có thể do mạng yếu hoặc chưa kết nối internet....")
                .font(AppFont.beVietnamPro(13))
                .foregroundStyle(AppColor.payMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Tải lại") {
                Task { await store.loadFirstPage(filter: filter) }
            }
            .buttonStyle(.plain)
            .font(AppFont.beVietnamPro(14, .semibold))
            .foregroundStyle(AppColor.brand)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AppColor.brand, lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Search debounce

    private func triggerSearchOrReload() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            if isSearchMode {
                await store.search(
                    filter: filter,
                    query: searchText.trimmingCharacters(in: .whitespaces),
                    dateFrom: dateStart,
                    dateTo: dateEnd
                )
            } else {
                await store.loadFirstPage(filter: filter)
            }
        }
    }

    // MARK: - Group theo ngày

    private struct DayGroup {
        let label: String
        let items: [TransactionEntity]
    }

    private func groupedByDay(_ items: [TransactionEntity]) -> [DayGroup] {
        let formatter = ISO8601DateFormatter.withFractionalSeconds
        let fallbackFormatter = ISO8601DateFormatter.standard

        var order: [String] = []
        var buckets: [String: [TransactionEntity]] = [:]

        for tx in items {
            let date = formatter.date(from: tx.createdAt) ?? fallbackFormatter.date(from: tx.createdAt) ?? Date()
            let label = dayLabel(for: date)
            if buckets[label] == nil {
                buckets[label] = []
                order.append(label)
            }
            buckets[label]?.append(tx)
        }

        return order.map { DayGroup(label: $0, items: buckets[$0] ?? []) }
    }

    private func dayLabel(for date: Date) -> String {
        if Calendar.app.isDateInToday(date) { return "Hôm nay" }
        if Calendar.app.isDateInYesterday(date) { return "Hôm qua" }
        return DateFormatter.app("dd/MM/yyyy").string(from: date)
    }

    private func timeLabel(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter.withFractionalSeconds.date(from: iso)
            ?? ISO8601DateFormatter.standard.date(from: iso) else { return iso }
        return DateFormatter.app("HH:mm").string(from: date)
    }

    private func signedAmount(_ tx: TransactionEntity) -> String {
        let signed = tx.isIncome ? tx.amountValue : -tx.amountValue
        return Int(signed).vndSigned
    }
}

#Preview {
    HistoryView(onBack: {})
}
