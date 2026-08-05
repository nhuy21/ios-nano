//
//  View+OnChangeCompat.swift
//  nano ewallet
//
//  Lớp tương thích cho `.onChange(of:initial:_:)` — API 2 tham số (oldValue, newValue) và
//  tham số `initial:` đều là iOS 17+, còn deployment target của app là 16.0.
//
//  Toàn bộ chỗ gọi trong app dùng `.onChangeCompat(...)` với ĐÚNG chữ ký cũ (2 tham số,
//  `initial:` tuỳ chọn) nên không phải sửa từng closure — chỉ đổi tên modifier.
//

import SwiftUI

extension View {
    /// Bản 2 tham số `(oldValue, newValue)` — chạy được từ iOS 13.
    ///
    /// `initial: true`: gọi NGAY một lần lúc view xuất hiện với `oldValue == newValue`.
    /// Cần cho các cờ deep link ở `MainTabView`: cờ có thể đã được bật TRƯỚC khi view xuất
    /// hiện (bootstrap chạy ở Splash), thiếu nó thì không bao giờ khớp và màn không mở.
    func onChangeCompat<V: Equatable>(
        of value: V,
        initial: Bool = false,
        _ action: @escaping (_ oldValue: V, _ newValue: V) -> Void
    ) -> some View {
        modifier(OnChangeCompatModifier(value: value, initial: initial, action: action))
    }

    /// Bản 1 tham số — nhận `newValue`, bỏ qua giá trị cũ.
    ///
    /// Tên KHÁC bản 2 tham số (không overload): closure `{ _, _ in }` sẽ nhập nhằng nếu hai
    /// overload chỉ khác số tham số, Swift không tự chọn được.
    func onChangeNewCompat<V: Equatable>(
        of value: V,
        initial: Bool = false,
        _ action: @escaping (_ newValue: V) -> Void
    ) -> some View {
        modifier(OnChangeCompatModifier(value: value, initial: initial, action: { _, new in action(new) }))
    }
}

private struct OnChangeCompatModifier<V: Equatable>: ViewModifier {
    let value: V
    let initial: Bool
    let action: (V, V) -> Void

    /// Giữ giá trị TRƯỚC lần đổi gần nhất — `.onChange(of:perform:)` (iOS 14) chỉ đưa
    /// `newValue`, phải tự nhớ `oldValue` qua state riêng.
    @State private var previous: V?

    func body(content: Content) -> some View {
        content
            .onAppear {
                // Chốt mốc "giá trị lúc view xuất hiện" TRƯỚC — không phụ thuộc `initial`, để
                // lần đổi đầu tiên (khi `initial == false`) so đúng với giá trị ban đầu thật,
                // không bị lệch thành "oldValue == newValue" một cách giả tạo.
                guard previous == nil else { return }
                previous = value
                if initial { action(value, value) }
            }
            .onChange(of: value) { newValue in
                let old = previous ?? newValue
                previous = newValue
                action(old, newValue)
            }
    }
}
