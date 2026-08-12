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

    /// Lớp phủ dạng dialog, hiện và ẩn NGAY LẬP TỨC.
    ///
    /// Không dùng `fullScreenCover`/`sheet`: cả hai luôn chạy transition trượt của UIKit,
    /// không tham số nào tắt được. Cách duy nhất chắc chắn là không đưa việc trình bày cho
    /// UIKit — `.overlay` chỉ là một lớp trong cây view SwiftUI nên không có transition nào
    /// để mà tắt.
    ///
    /// (Đã thử `UIView.setAnimationsEnabled(false)` quanh chỗ đổi cờ. Không ăn: đó là cờ toàn
    /// cục, phải bọc đúng mọi đường bật/tắt, và việc bật lại ở cuối run loop lệch nhịp với
    /// transition nên còn sinh giật.)
    ///
    /// LƯU Ý về thanh tab: thanh tab nổi của app được `MainTabView` vẽ SAU nội dung trong một
    /// `ZStack`, nên lớp phủ gắn bên trong màn (Home/Cá nhân) sẽ bị nó đè lên, hở một mảng ở
    /// đáy. Ở những màn đó phải dùng `tabBarOverlay(...)` để đẩy lớp phủ lên vẽ ở cấp
    /// `MainTabView`. Các màn đứng ngoài `MainTabView` (màn quét QR, nhận tiền) thì dùng thẳng
    /// modifier này.
    func instantOverlayCover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        overlay {
            if isPresented.wrappedValue {
                content()
                    // Nhận chạm trên toàn màn: nội dung tự vẽ nền mờ và tự bắt tap để đóng,
                    // thiếu dòng này thì vùng trong suốt để lọt chạm xuống màn phía dưới.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }
        }
    }

    /// Bản `item:` của `instantOverlayCover` — cho lớp phủ mang theo dữ liệu (danh sách tài
    /// khoản để chọn...) thay vì chỉ một cờ bật/tắt.
    func instantOverlayCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        overlay {
            if let value = item.wrappedValue {
                content(value)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }
        }
    }

    /// Gửi một lớp phủ LÊN `MainTabView` để nó vẽ trên cùng, trên cả thanh tab nổi.
    ///
    /// Dùng ở màn gốc của tab (Home, Cá nhân) thay cho `instantOverlayCover`. Lý do: thanh tab
    /// được vẽ sau nội dung trong `ZStack` của `MainTabView`, nên mọi `.overlay` gắn bên trong
    /// màn đều nằm dưới nó.
    ///
    /// Vẫn là view SwiftUI thuần, không qua `fullScreenCover`, nên hiện/ẩn tức thì.
    /// - Parameter id: định danh ỔN ĐỊNH của lớp phủ (đặt tay, ví dụ "quickTopUp"). Bắt buộc
    ///   vì `ForEach` bên `MainTabView` dựa vào nó: id đổi mỗi lần preference tính lại thì
    ///   SwiftUI dựng lại view và xoá sạch state — số tiền đang gõ dở sẽ bay mất.
    func tabBarOverlay<Content: View>(
        _ id: String,
        isPresented: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        preference(
            key: TopOverlayKey.self,
            value: isPresented ? [TopOverlayEntry(id: id, content: AnyView(content()))] : []
        )
    }

    /// Bản `item:` của `tabBarOverlay`.
    func tabBarOverlay<Item: Identifiable, Content: View>(
        _ id: String,
        item: Item?,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        preference(
            key: TopOverlayKey.self,
            value: item.map { [TopOverlayEntry(id: id, content: AnyView(content($0)))] } ?? []
        )
    }

    /// Gắn ở `MainTabView`, NGOÀI `ZStack` chứa thanh tab: vẽ mọi lớp phủ mà màn con gửi lên.
    func drawsTopOverlays() -> some View {
        overlayPreferenceValue(TopOverlayKey.self) { entries in
            ForEach(entries) { entry in
                entry.content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }
        }
    }
}

/// Một lớp phủ do màn con gửi lên. `id` do nơi gọi đặt và phải ổn định giữa các lần dựng lại
/// — xem `tabBarOverlay(_:isPresented:content:)`.
struct TopOverlayEntry: Identifiable {
    let id: String
    let content: AnyView
}

/// Kênh đưa lớp phủ từ màn con lên `MainTabView`.
///
/// Gộp bằng cách nối danh sách, không phải "cái sau đè cái trước": hai tab cùng sống trong
/// `TabView` nên cả hai đều phát preference, mà chỉ tab đang chọn mới có lớp phủ thật — tab
/// còn lại phát danh sách rỗng nên nối vào là vô hại.
struct TopOverlayKey: PreferenceKey {
    static let defaultValue: [TopOverlayEntry] = []

    static func reduce(value: inout [TopOverlayEntry], nextValue: () -> [TopOverlayEntry]) {
        value.append(contentsOf: nextValue())
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
