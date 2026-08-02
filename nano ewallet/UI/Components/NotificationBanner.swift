//
//  NotificationBanner.swift
//  nano ewallet
//
//  Mirror NotificationOverlay.kt — 2 phần:
//   - `notificationWatcher()`: poll hộp thư khi app foreground. Push FCM có thể tắt
//     (user từ chối quyền) hoặc tới chậm, nên vẫn cần nhịp poll để gần realtime.
//   - `NotificationBanner`: banner trượt từ đỉnh khi có thông báo MỚI lúc đang dùng
//     app — iOS không tự hiện banner hệ thống khi app đang mở.
//

import SwiftUI
import Combine

/// Nhịp poll khi app foreground. Bản Android để 8s (hạ từ 25s vì trễ quá lâu khi push
/// tắt/chậm) — giữ nguyên con số đó.
private let notificationPollInterval: TimeInterval = 8

extension View {
    /// Đặt MỘT lần ở gốc cây đã đăng nhập. Tự dừng khi app xuống nền: `.task` bị huỷ
    /// theo vòng đời view nên không cần gỡ observer thủ công như Android.
    func notificationWatcher() -> some View {
        modifier(NotificationWatcherModifier())
    }
}

private struct NotificationWatcherModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                if AuthStore.shared.accessToken != nil {
                    await NotificationStore.shared.refresh()
                }
                try? await Task.sleep(nanoseconds: UInt64(notificationPollInterval * 1_000_000_000))
            }
        }
    }
}

/// Banner báo thông báo mới — trượt từ đỉnh, tự ẩn sau ~4,5s, chạm để mở hộp thư.
@MainActor
struct NotificationBanner: View {
    let onOpen: () -> Void

    @State private var current: AppNotification?
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        VStack {
            if let current {
                banner(current)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.25), value: current?.id)
        .onReceive(NotificationStore.shared.newNotification) { notification in
            current = notification
            hideTask?.cancel()
            hideTask = Task {
                try? await Task.sleep(nanoseconds: 4_500_000_000)
                guard !Task.isCancelled else { return }
                current = nil
            }
        }
    }

    private func banner(_ notification: AppNotification) -> some View {
        Button {
            current = nil
            hideTask?.cancel()
            onOpen()
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(AppColor.brandSoft)
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(AppColor.brand)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(notification.title)
                        .font(AppFont.beVietnamPro(14, .bold))
                        .foregroundStyle(AppColor.payInk)
                        .lineLimit(1)
                    Text(notification.body)
                        .font(AppFont.beVietnamPro(12.5))
                        .foregroundStyle(AppColor.payMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
