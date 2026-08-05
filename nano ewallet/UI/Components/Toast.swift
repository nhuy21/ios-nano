//
//  Toast.swift
//  nano ewallet
//
//  Thông báo ngắn nổi lên từ đáy màn rồi tự tắt — thay `Toast.makeText(...).show()` bên
//  Android. iOS không có API tương đương nên phải tự dựng.
//

import SwiftUI

/// Trạng thái + hẹn giờ tự tắt của một toast. Giữ trong `@StateObject` ở màn cần dùng.
///
/// Là class (không phải `@State String?`) để hàm `show` tự huỷ được timer của lần trước:
/// bấm copy liên tục thì mỗi lần bấm phải gia hạn lại 2.5s, chứ không để timer cũ tắt sớm
/// thông báo vừa hiện.
@MainActor
final class ToastState: ObservableObject {
    @Published private(set) var message: String?

    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, duration: TimeInterval = 2.5) {
        self.message = message
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}

extension View {
    /// Gắn lớp toast vào màn. `bottomPadding` tính từ đáy vùng an toàn — mặc định 30pt.
    func toast(_ state: ToastState, bottomPadding: CGFloat = 30) -> some View {
        overlay(alignment: .bottom) {
            if let message = state.message {
                // Giữ đúng style toast đã dùng ở `ReceiveQrView` (nền đen 0.75, chữ 13,
                // capsule) để hai màn nhìn như một.
                Text(message)
                    .font(AppFont.beVietnamPro(13))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .padding(.horizontal, 24)
                    .padding(.bottom, bottomPadding)
                    .transition(.opacity)
                    // Không nhận chạm: toast nổi trên nội dung, ăn chạm sẽ chặn đúng vùng
                    // nút bấm nằm dưới nó.
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.25), value: state.message)
    }
}
