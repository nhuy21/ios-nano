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
    ///
    /// PHẢI có CẢ HAI modifier: `toolbar(.hidden,...)` chỉ ẩn NỘI DUNG thanh nav (title,
    /// nút), còn NỀN của nó là thứ riêng biệt do `toolbarBackground(.hidden,...)` quản.
    /// Thiếu cái thứ hai thì màn có nền tự vẽ (ảnh/gradient tràn lên status bar) vẫn bị
    /// dải trắng đục của nav bar đè lên đúng vùng status bar.
    /// Từ iOS 18 SDK, `toolbarBackground(_:for:)` đổi tên thành
    /// `toolbarBackgroundVisibility(_:for:)`; bản cũ không còn ăn trên iOS 18+/26 nên phải
    /// gọi bản mới khi máy đủ phiên bản, giữ bản cũ cho iOS 16-17.
    @ViewBuilder
    func hidesSystemNavigationBar() -> some View {
        if #available(iOS 18.0, *) {
            toolbar(.hidden, for: .navigationBar)
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        } else {
            toolbar(.hidden, for: .navigationBar)
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    /// Tô nền cho cả màn, tràn phủ luôn vùng safe area trên/dưới — dùng thay
    /// `.background(...)` ở modifier NGOÀI CÙNG của mỗi màn, để không hở dải trắng/xám của
    /// hệ thống ở status bar và home indicator.
    /// `.frame(maxWidth:maxHeight:)` là phần BẮT BUỘC đi trước: `VStack`/`ScrollView` chỉ cao
    /// bằng nội dung, tô nền theo nó thì `ignoresSafeArea` chẳng có gì để giãn ra — đó là lý
    /// do các màn khác vẫn hở dải trắng ở status bar trong khi `SplashView` (vốn đã tự ép
    /// giãn hết khung trước khi tô nền) thì phủ kín.
    /// - Parameter alignment: nội dung canh về đâu khi khung bị ép giãn hết màn. Mặc định
    ///   `.top` để màn canh trên (Login, Register...) không bị dồn ra giữa; màn vốn canh giữa
    ///   truyền `.center`.
    func screenBackground(_ color: Color, alignment: Alignment = .top) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .background(color.ignoresSafeArea())
    }
}
