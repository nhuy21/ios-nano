//
//  TabBarVisibility.swift
//  nano ewallet
//
//  Thanh tab nổi nằm trong ZStack của MainTabView nên mặc định đè lên MỌI thứ, kể cả
//  các màn con được push trong NavigationStack riêng của Home/Settings.
//
//  Home/Settings tự giữ `path` của mình, MainTabView không thấy được. Thay vì nâng
//  toàn bộ path lên (đổi chữ ký 2 màn), mỗi màn chỉ báo lên "stack của tôi đang rỗng
//  hay không" qua preference — MainTabView đọc và ẩn thanh tab khi đã push vào màn con.
//

import SwiftUI

struct TabBarVisibilityKey: PreferenceKey {
    static let defaultValue = true

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        // Chỉ cần 1 màn báo "đang ở màn con" là ẩn thanh tab.
        value = value && nextValue()
    }
}

extension View {
    /// Gắn ở màn gốc của mỗi tab: `true` khi đang đứng ở màn gốc (hiện thanh tab),
    /// `false` khi đã push sang màn con.
    func showsTabBar(_ visible: Bool) -> some View {
        preference(key: TabBarVisibilityKey.self, value: visible)
    }
}
