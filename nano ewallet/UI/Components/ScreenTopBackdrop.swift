//
//  ScreenTopBackdrop.swift
//  nano ewallet
//
//  Kênh để màn nói cho `MainTabView` biết màu cần TRÀN lên dải status bar.
//
//  Vì sao cần: `MainTabView` để hệ thống lo safe area trên (xem chú thích ở đó), nên vùng
//  status bar KHÔNG còn thuộc khung của trang — nền của màn dù có `ignoresSafeArea()` cũng
//  chẳng có gì để giãn ra, dải trên sẽ trơ nền trắng của cửa sổ. Màn phát màu lên đây,
//  `MainTabView` vẽ nó PHÍA SAU `TabView` (chỗ duy nhất còn với tới được dải đó), nhờ vậy
//  NỀN thì tràn mà NỘI DUNG vẫn giữ nguyên khoảng trống dưới đồng hồ.
//
//  Không mở lại `ignoresSafeArea` ở `TabView` được: mở đỉnh ra thì `NavigationStack` bên trong
//  (bọc UIKit) báo top inset = 0 cho mọi màn trên iOS 16→18.x và header đè lên đồng hồ.
//

import SwiftUI

struct ScreenTopBackdropKey: PreferenceKey {
    /// `nil` = màn không yêu cầu gì, giữ nguyên màu màn trước đó trong cây đã phát.
    static let defaultValue: Color? = nil

    /// Màn phát SAU thì thắng. Màn push vào nằm sau màn gốc trong cây nên đúng màn đang hiển
    /// thị quyết định màu dải trên; pop ra thì giá trị của màn gốc tự có tác dụng lại.
    static func reduce(value: inout Color?, nextValue: () -> Color?) {
        if let next = nextValue() { value = next }
    }
}

extension View {
    /// Khai báo màu tràn lên dải status bar cho màn này.
    ///
    /// `screenBackground(_:)` đã tự gọi hàm này với màu nền của màn, nên phần lớn màn không
    /// phải làm gì. Chỉ gọi tay ở màn có nền GRADIENT/ảnh (truyền màu ở mép TRÊN của gradient),
    /// vì những màn đó không dùng `screenBackground`.
    func screenTopBackdrop(_ color: Color?) -> some View {
        preference(key: ScreenTopBackdropKey.self, value: color)
    }
}
