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
    /// rồi tự fade lấy — xem `withoutPresentationAnimation`, phải bọc ở nơi ĐỔI CỜ, cả lúc
    /// bật lẫn lúc tắt.
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

    /// Lưới chặn cho những lần đóng do CHÍNH iOS khởi xướng (vuốt xuống, hệ thống thu hồi
    /// lớp phủ) — lúc đó không có chỗ nào của app chạy để mà bọc.
    ///
    /// Chặn trong setter chứ không phải `onChange` vì `onChange` chạy sau khi state đã cập
    /// nhật, tức sau khi UIKit dựng xong transition — lúc đó tắt cũng không kịp.
    ///
    /// KHÔNG thay được việc bọc ở nơi gọi: `onDismiss` của app set thẳng biến `@State` gốc,
    /// không đi qua binding này, nên đường đóng thường gặp nhất vẫn phải tự bọc.
    private var gate: Binding<Bool> {
        Binding(
            get: { isPresented },
            set: { newValue in
                if !newValue { suppressUIKitAnimationForThisRunLoop() }
                isPresented = newValue
            }
        )
    }

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: gate) {
                overlay()
                    .opacity(visible ? 1 : 0)
                    .transparentSheetBackground()
                    .onAppear {
                        withAnimation(.easeOut(duration: instantOverlayFade)) { visible = true }
                    }
                    // Tắt PHĂNG, không `withAnimation`: đóng phải là tức thì. Cũng là để lần
                    // mở kế tiếp bắt đầu lại từ trạng thái ẩn, nếu không sẽ mất fade.
                    .onDisappear { visible = false }
            }
    }
}

/// Xem `instantOverlayCover(item:content:)`.
private struct InstantOverlayCoverItem<Item: Identifiable, Overlay: View>: ViewModifier {
    @Binding var item: Item?
    @ViewBuilder let overlay: (Item) -> Overlay

    @State private var visible = false

    /// Xem `gate` ở `InstantOverlayCover`.
    private var gate: Binding<Item?> {
        Binding(
            get: { item },
            set: { newValue in
                if newValue == nil { suppressUIKitAnimationForThisRunLoop() }
                item = newValue
            }
        )
    }

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: gate) { value in
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

/// Tắt animation của UIKit cho tới hết vòng lặp run loop hiện tại.
///
/// `UIView.setAnimationsEnabled` là cờ TOÀN CỤC nên bắt buộc phải bật lại, và mốc "cuối run
/// loop hiện tại" là mốc duy nhất đúng: bật lại sớm hơn thì transition chưa kịp dựng nên cờ
/// mất tác dụng, muộn hơn thì nuốt luôn animation của phần khác trong app.
///
/// Gọi lồng nhau vẫn an toàn: mỗi lần gọi xếp thêm một lượt bật lại, lượt cuối chốt về `true`.
@MainActor
private func suppressUIKitAnimationForThisRunLoop() {
    UIView.setAnimationsEnabled(false)
    DispatchQueue.main.async { UIView.setAnimationsEnabled(true) }
}

/// Chạy `body` (chỗ bật HOẶC tắt cờ trình bày) mà không kèm animation trượt của UIKit.
///
/// Phải bọc ở nơi gọi chứ không đặt trong modifier được: cờ cần đang tắt đúng lúc UIKit dựng
/// transition, mà tới khi modifier thấy cờ đổi thì transition đã bắt đầu rồi.
///
/// Bọc CẢ hai chiều: mở lẫn đóng. Quên chiều đóng thì lớp phủ vẫn trượt xuống từ từ.
@MainActor
func withoutPresentationAnimation(_ body: () -> Void) {
    suppressUIKitAnimationForThisRunLoop()
    body()
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
