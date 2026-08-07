//
//  NotificationsView.swift
//  nano ewallet
//
//  Mirror NotificationScreen.kt — hộp thư thông báo: 3 tab (Tất cả / Chưa đọc /
//  Hệ thống), bấm dòng thì đánh dấu đã đọc rồi mở đúng đích theo `data`:
//  giao dịch → bill, xin tiền → cuộc thoại.
//

import SwiftUI
import Combine

@MainActor
struct NotificationsView: View {
    let onClose: () -> Void
    /// Mở cuộc thoại xin tiền — Home sở hữu NavigationStack nên đẩy route từ ngoài vào.
    var onOpenConversation: (String) -> Void = { _ in }

    private enum Tab: Int, CaseIterable {
        case all, unread, system

        var title: String {
            switch self {
            case .all: return "Tất cả"
            case .unread: return "Chưa đọc"
            case .system: return "Hệ thống"
            }
        }
    }

    private enum NsColor {
        static let accent = Color(hex: 0x00A85E)
        static let iconBorder = Color(hex: 0xE4EDE8)
        static let unreadRow = Color(hex: 0xF3FBF6)
    }

    @StateObject private var store = NotificationStore.shared

    @State private var selectedTab: Tab = .all
    @State private var isLoading = true
    @State private var hasError = false
    @State private var billTransaction: TransactionEntity?
    /// Chặn mở trùng khi đang tải chi tiết giao dịch (bấm nhanh 2 lần).
    @State private var isOpeningBill = false

    private var visibleItems: [AppNotification] {
        switch selectedTab {
        case .unread: return store.items.filter { !$0.isRead }
        // "Hệ thống" gồm SYSTEM + KYC — tức mọi thứ không phải giao dịch.
        case .system: return store.items.filter { $0.type != "TRANSACTION" }
        case .all: return store.items
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(AppColor.payDivider)
                .frame(height: 1)
                .padding(.horizontal, 20)

            tabs

            content
        }
        .screenBackground(Color.white)
        .task { await load() }
        .sheet(item: $billTransaction) { tx in
            TransactionDetailSheet(tx: tx, onDismiss: { billTransaction = nil })
        }
    }

    private func load() async {
        isLoading = true
        let ok = await store.refresh()
        hasError = !ok && store.items.isEmpty
        isLoading = false
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                if store.unreadCount > 0 {
                    Circle()
                        .fill(NsColor.accent)
                        .frame(width: 9, height: 9)
                        .overlay { Circle().strokeBorder(Color.white, lineWidth: 1.5) }
                        .offset(x: -8, y: 8)
                }
            }

            Text("Thông báo")
                .font(AppFont.beVietnamPro(20, .bold))
                .foregroundStyle(AppColor.payInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)

            if store.unreadCount > 0 {
                Button {
                    Task { await store.markAllRead() }
                } label: {
                    Text("Đọc tất cả")
                        .font(AppFont.beVietnamPro(13, .semibold))
                        .foregroundStyle(NsColor.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppColor.payInk)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Đóng")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Tabs

    private var tabs: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(AppColor.payDivider)
                .frame(height: 1)

            HStack(alignment: .bottom, spacing: 24) {
                ForEach(Tab.allCases, id: \.rawValue) { tab in
                    tabItem(tab)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 20)
        }
    }

    private func tabItem(_ tab: Tab) -> some View {
        let isActive = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text(tab.title)
                        .font(AppFont.beVietnamPro(15, isActive ? .bold : .semibold))
                        .foregroundStyle(isActive ? NsColor.accent : AppColor.payMuted)
                        .lineLimit(1)
                    if tab == .unread && store.unreadCount > 0 {
                        Text(store.unreadCount > 9 ? "9+" : "\(store.unreadCount)")
                            .font(AppFont.beVietnamPro(11, .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(NsColor.accent, in: Capsule())
                    }
                }
                .padding(.top, 14)

                Spacer().frame(height: 13)

                Rectangle()
                    .fill(isActive ? NsColor.accent : Color.clear)
                    .frame(height: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Nội dung

    @ViewBuilder
    private var content: some View {
        if isLoading && store.items.isEmpty {
            ProgressView()
                .tint(NsColor.accent)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            Spacer()
        } else if hasError && store.items.isEmpty {
            VStack(spacing: 6) {
                Text("Không tải được thông báo")
                    .font(AppFont.beVietnamPro(15, .semibold))
                    .foregroundStyle(AppColor.payInk)
                Button("Thử lại") { Task { await load() } }
                    .buttonStyle(.plain)
                    .font(AppFont.beVietnamPro(13, .bold))
                    .foregroundStyle(NsColor.accent)
                    .padding(8)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 72)
            Spacer()
        } else if visibleItems.isEmpty {
            emptyState
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                        row(item)
                        if index != visibleItems.count - 1 {
                            Rectangle()
                                .fill(AppColor.payDivider)
                                .frame(height: 1)
                                .padding(.leading, 68)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        let text: (String, String)
        switch selectedTab {
        case .unread:
            text = ("Không có thông báo chưa đọc", "Bạn đã xem hết thông báo mới")
        case .system:
            text = ("Chưa có thông báo hệ thống", "Các cập nhật hệ thống sẽ hiển thị ở đây")
        case .all:
            text = ("Chưa có thông báo", "Thông báo mới sẽ hiển thị ở đây")
        }
        return VStack(spacing: 6) {
            Text(text.0)
                .font(AppFont.beVietnamPro(15, .semibold))
                .foregroundStyle(AppColor.payInk)
            Text(text.1)
                .font(AppFont.beVietnamPro(13))
                .foregroundStyle(AppColor.payMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
    }

    private func row(_ item: AppNotification) -> some View {
        let style = Self.iconStyle(for: item.type)
        let isUnread = !item.isRead
        return Button {
            handleTap(item)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 40, height: 40)
                    .overlay { Circle().strokeBorder(NsColor.iconBorder, lineWidth: 1.5) }
                    .overlay {
                        Image(systemName: style.symbol)
                            .font(.system(size: 18))
                            .foregroundStyle(style.tint)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(AppFont.beVietnamPro(15, .bold))
                        .foregroundStyle(AppColor.payInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(item.body)
                        .font(AppFont.beVietnamPro(13))
                        .foregroundStyle(AppColor.payMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(Self.relativeTime(item.createdAt))
                        .font(AppFont.beVietnamPro(11, isUnread ? .semibold : .regular))
                        .foregroundStyle(isUnread ? NsColor.accent : AppColor.payMuted)
                        .padding(.top, 1)
                }

                if isUnread {
                    Circle()
                        .fill(NsColor.accent)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isUnread ? NsColor.unreadRow : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bấm vào thông báo

    private func handleTap(_ item: AppNotification) {
        if !item.isRead {
            Task { await store.markRead(id: item.id) }
        }
        guard let ref = item.data else { return }

        if let txId = ref.txId {
            guard !isOpeningBill else { return }
            isOpeningBill = true
            Task {
                defer { isOpeningBill = false }
                billTransaction = try? await TransactionService.getById(txId)
            }
            return
        }

        // Kiểm khoảng trắng chứ không chỉ rỗng (mirror `isNullOrBlank` bên Kotlin) —
        // BE trả username toàn dấu cách thì mở cuộc thoại rỗng, không tra được ai.
        if ref.requestId != nil,
           let other = ref.otherBkUsername,
           !other.trimmingCharacters(in: .whitespaces).isEmpty {
            onOpenConversation(other)
        }
    }

    // MARK: - Hiển thị

    /// Icon + màu theo `NotificationType` bên backend.
    private static func iconStyle(for type: String) -> (symbol: String, tint: Color) {
        switch type {
        case "TRANSACTION": return ("arrow.left.arrow.right", Color(hex: 0x22A45D))
        case "KYC": return ("checkmark.shield.fill", Color(hex: 0x2C93E8))
        default: return ("megaphone.fill", NsColor.accent) // SYSTEM + mặc định
        }
    }

    /// ISO-8601 -> nhãn tương đối: Vừa xong / x phút / x giờ / Hôm qua / dd/MM/yyyy.
    private static func relativeTime(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter.withFractionalSeconds.date(from: iso)
            ?? ISO8601DateFormatter.standard.date(from: iso) else { return "" }

        let minutes = max(Int(Date().timeIntervalSince(date) / 60), 0)
        switch minutes {
        case ..<1: return "Vừa xong"
        case ..<60: return "\(minutes) phút trước"
        case ..<(24 * 60): return "\(minutes / 60) giờ trước"
        case ..<(48 * 60): return "Hôm qua"
        default:
            return DateFormatter.app("dd/MM/yyyy").string(from: date)
        }
    }
}

#Preview {
    NotificationsView(onClose: {})
}
