//
//  View+TransparentSheet.swift
//  nano ewallet
//
//  Làm nền sheet trong suốt để dialog "nổi" trên nền mờ, thay `presentationBackground(.clear)`
//  (iOS 16.4, cao hơn deployment target 16.0).
//
//  Cách làm: nhét một `UIViewRepresentable` rỗng vào cây view của sheet, rồi leo ngược
//  `superview` để tìm view nền do UIKit dựng cho sheet và set `backgroundColor = .clear`.
//  Không có API SwiftUI nào làm được việc này trước 16.4.
//

import SwiftUI

extension View {
    /// Gắn vào nội dung sheet (KHÔNG phải vào view gọi `.sheet`) để nền sheet trong suốt.
    ///
    /// Nội dung sheet phải tự vẽ nền mờ của nó (thường là `Color.black.opacity(...)` phủ
    /// toàn màn) — modifier này chỉ bỏ tấm nền trắng mặc định đi.
    func transparentSheetBackground() -> some View {
        background(TransparentSheetBackground())
    }
}

/// View vô hình, chỉ tồn tại để lấy `UIView` thật rồi sửa nền của sheet chứa nó.
private struct TransparentSheetBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = ProbeView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    /// Phải làm trong `didMoveToWindow` chứ không phải `makeUIView`: lúc `makeUIView` chạy,
    /// view chưa được gắn vào cây nên `superview` còn nil, không có gì để leo.
    private final class ProbeView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            clearAncestorBackgrounds()
        }

        /// Xoá nền của TẤT CẢ view tổ tiên trong phạm vi sheet.
        ///
        /// Dừng ở view gốc của view controller đang host (`next` là `UIViewController`):
        /// leo tiếp lên tới `UIWindow` sẽ xoá luôn nền của màn hình phía sau, làm cả app
        /// trắng xoá khi sheet mở.
        ///
        /// Xoá cả chuỗi thay vì chỉ một cấp: số lớp trung gian UIKit chèn vào không cố định
        /// giữa các bản iOS, nhắm đúng một cấp là hôm nay đúng mai sai.
        private func clearAncestorBackgrounds() {
            var current: UIView? = superview
            while let view = current {
                view.backgroundColor = .clear
                if view.next is UIViewController { return }
                current = view.superview
            }
        }
    }
}
