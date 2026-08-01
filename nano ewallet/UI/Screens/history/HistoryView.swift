//
//  HistoryView.swift
//  nano ewallet
//
//  Mirror HistoryScreen.kt — filter tab (Tất cả/Nhận/Chuyển), search + date range
//  (debounce 400ms), infinite scroll (cursor = createdAt item cuối), group theo ngày.
//

import SwiftUI
import Combine

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
        .background(Color(hex: 0xF7F8FA))
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

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppColor.payInk)
                    .frame(width: 40, height: 40)
                    .background(Color.white)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .circleButtonShadow()

            Text("Lịch sử giao dịch")
                .font(AppFont.beVietnamPro(18, .bold))
                .foregroundStyle(AppColor.payInk)

            Spacer()

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
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func headerIconButton(systemImage: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16))
                .foregroundStyle(isActive ? AppColor.brand : AppColor.payInk)
                .frame(width: 40, height: 40)
                .background(isActive ? AppColor.brandSoft : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search bar + date chip

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(AppColor.payMuted)
            TextField("Tìm theo tên, nội dung...", text: $searchText)
                .font(.system(size: 14))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(AppColor.payMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Xoá")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color(hex: 0x784628).opacity(0x0A / 255.0), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var dateChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 12))
            Text(rangeLabel)
                .font(.system(size: 12, weight: .medium))
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
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        let shortFormatter = DateFormatter()
        shortFormatter.dateFormat = "dd/MM"

        switch (dateStart, dateEnd) {
        case (nil, nil):
            return "Mọi ngày"
        case let (start?, end?) where Calendar.current.isDate(start, inSameDayAs: end):
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
                        .padding(.bottom, 12)

                    if isSearchMode && store.isSearching {
                        ProgressView().tint(AppColor.brand).padding(.top, 40)
                    } else if isSearchMode, let searchError = store.searchError {
                        Text(searchError)
                            .font(.system(size: 13))
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

    private var filterTabs: some View {
        HStack(spacing: 4) {
            ForEach(HistoryFilter.allCases, id: \.self) { tab in
                let isActive = filter == tab
                Button {
                    filter = tab
                    triggerSearchOrReload()
                } label: {
                    Text(tab.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isActive ? AppColor.brand : AppColor.payMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(isActive ? AppColor.brandSoft : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white)
        .clipShape(Capsule())
        .shadow(color: Color(hex: 0x784628).opacity(0x0A / 255.0), radius: 4, x: 0, y: 2)
    }

    private var transactionGroups: some View {
        let groups = groupedByDay(store.items)
        return VStack(spacing: 12) {
            ForEach(groups, id: \.label) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColor.payMuted)
                        .padding(.leading, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, tx in
                            if index > 0 {
                                Rectangle().fill(Color(hex: 0xECECEC)).frame(height: 1).padding(.leading, 42)
                            }
                            row(tx)
                        }
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color(hex: 0x784628).opacity(0x0A / 255.0), radius: 4, x: 0, y: 2)
                }
            }

            if store.isLoadingMore {
                ProgressView().tint(AppColor.brand).padding(.top, 12)
            } else if store.noMoreData && !isSearchMode {
                Text("Đã hiển thị toàn bộ giao dịch")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.payMuted)
                    .padding(.top, 12)
            } else if !isSearchMode {
                // Trigger vô hình gần đáy để load thêm khi cuộn tới.
                Color.clear.frame(height: 1)
                    .onAppear { Task { await store.loadMore(filter: filter) } }
            }
        }
    }

    private func row(_ tx: TransactionEntity) -> some View {
        let icon = TransactionDisplay.iconStyle(for: tx)
        return Button {
            detailTransaction = tx
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(icon.background)
                    .frame(width: 30, height: 30)
                    .overlay {
                        TransactionIcon(kind: icon.icon, tint: icon.tint)
                            .frame(width: 16, height: 16)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(TransactionDisplay.listTitle(for: tx))
                        .font(AppFont.beVietnamPro(14, .semibold))
                        .foregroundStyle(AppColor.payInk)
                        .lineLimit(2)
                    Text(timeLabel(tx.createdAt))
                        .font(.system(size: 12))
                        .foregroundStyle(AppColor.payMuted)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(signedAmount(tx))
                        .font(AppFont.beVietnamPro(14, .semibold))
                        .foregroundStyle(TransactionDisplay.amountColor(for: tx))
                    if let balance = tx.cachedBalanceAfterValue {
                        Text("Số dư: \(Int(balance).vndFormatted)")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColor.payMuted)
                    }
                }
            }
            .padding(.horizontal, 16)
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
                .font(.system(size: 13))
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
                .font(.system(size: 13))
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
        if Calendar.current.isDateInToday(date) { return "Hôm nay" }
        if Calendar.current.isDateInYesterday(date) { return "Hôm qua" }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }

    private func timeLabel(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter.withFractionalSeconds.date(from: iso)
            ?? ISO8601DateFormatter.standard.date(from: iso) else { return iso }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func signedAmount(_ tx: TransactionEntity) -> String {
        let signed = tx.isIncome ? tx.amountValue : -tx.amountValue
        return Int(signed).vndSigned
    }
}

#Preview {
    HistoryView(onBack: {})
}
