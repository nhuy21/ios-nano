//
//  HidesSystemNavigationBar.swift
//  nano ewallet
//

import SwiftUI

extension View {
    /// Ẩn nav bar rỗng mà `NavigationStack` tự thêm vào mỗi màn được push.
    ///
    /// Toàn bộ màn trong app đều tự vẽ header/nút back riêng (mirror Android), nên nav
    /// bar hệ thống chỉ thừa ra một dải trắng ở đỉnh, đẩy nội dung xuống và làm phần
    /// cuối màn bị cắt. Phải gắn cho TỪNG màn (cả root lẫn destination) — đặt trên
    /// `NavigationStack` không có tác dụng với màn push sau đó.
    func hidesSystemNavigationBar() -> some View {
        toolbar(.hidden, for: .navigationBar)
    }
}
