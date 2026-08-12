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

    /// Như `fullScreenCover` nhưng KHÔNG trượt từ dưới lên — dialog hiện ra tại chỗ, mờ dần.
    ///
    /// `fullScreenCover` luôn dùng `.coverVertical` của UIKit; không có tham số nào tắt được,
    /// và bọc `withTransaction(.init(animation: nil))` quanh chỗ bật cờ cũng vô hiệu vì cú
    /// trượt do UIKit chạy chứ không phải SwiftUI. Cách còn lại là tắt animation ở tầng UIKit
    /// rồi tự fade lấy — xem `withoutPresentationAnimation`, phải gọi ở NƠI BẬT CỜ.
    ///
    /// Vẫn đi qua `fullScreenCover` chứ không phải `.overlay` để giữ đúng thứ hạng lớp: hộp
    /// chọn phải phủ lên cả thanh tab và thanh điều hướng, mà `.overlay` gắn trong cây view
    /// của tab thì nằm dưới chúng.
    func instantOverlayCover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(InstantOverlayCover(isPresented: isPresented, overlay: content))
    }

    /// Bản `item:` của `instantOverlayCover` — cho lớp phủ mang theo dữ liệu (danh sách tài
    /// khoản để chọn...) thay vì chỉ một cờ bật/tắt.
    func instantOverlayCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        modifier(InstantOverlayCoverItem(item: item, overlay: content))
    }
}

/// Thời lượng fade của lớp phủ. Ngắn cỡ này để cảm giác là "hiện ra ngay" chứ không phải
/// một animation nữa thay thế cho cú trượt.
private let instantOverlayFade: Double = 0.18

/// Xem `instantOverlayCover(isPresented:content:)`.
private struct InstantOverlayCover<Overlay: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder let overlay: () -> Overlay

    /// Tách khỏi `isPresented` để fade chạy SAU khi lớp phủ đã được gắn vào cây view. Dùng
    /// chung một biến thì nội dung xuất hiện cùng lúc với `opacity = 1`, không có gì để fade.
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isPresented) {
                overlay()
                    .opacity(visible ? 1 : 0)
                    .transparentSheetBackground()
                    .onAppear {
                        withAnimation(.easeOut(duration: instantOverlayFade)) { visible = true }
                    }
                    // Trả về false khi đóng, nếu không lần mở kế tiếp bắt đầu ở trạng thái
                    // đã hiện sẵn và mất luôn hiệu ứng fade.
                    .onDisappear { visible = false }
            }
    }
}

/// Xem `instantOverlayCover(item:content:)`.
private struct InstantOverlayCoverItem<Item: Identifiable, Overlay: View>: ViewModifier {
    @Binding var item: Item?
    @ViewBuilder let overlay: (Item) -> Overlay

    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $item) { value in
                overlay(value)
                    .opacity(visible ? 1 : 0)
                    .transparentSheetBackground()
                    .onAppear {
                        withAnimation(.easeOut(duration: instantOverlayFade)) { visible = true }
                    }
                    .onDisappear { visible = false }
            }
    }
}

/// Chạy `body` (thường là chỗ bật/tắt cờ trình bày) mà không kèm animation trượt của UIKit.
///
/// `UIView.setAnimationsEnabled(false)` phải đang có hiệu lực đúng lúc UIKit dựng transition,
/// nên phải bọc quanh CHÍNH lần đổi cờ chứ không đặt trong modifier — tới lúc modifier thấy
/// cờ đổi thì transition đã bắt đầu rồi.
///
/// Đây là cờ toàn cục: bật lại ở cuối vòng lặp run loop hiện tại. Sớm hơn thì transition chưa
/// dựng xong và cờ mất tác dụng; quên bật lại thì cả app đứng hình không còn animation nào.
@MainActor
func withoutPresentationAnimation(_ body: () -> Void) {
    UIView.setAnimationsEnabled(false)
    body()
    DispatchQueue.main.async { UIView.setAnimationsEnabled(true) }
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
