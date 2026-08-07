//
//  HidesSystemNavigationBar.swift
//  nano ewallet
//

import SwiftUI
import UIKit

/// Tắt cử chỉ vuốt-cạnh-màn để lùi. SwiftUI không có API cho việc này
/// (`navigationBarBackButtonHidden` chỉ ẩn NÚT, cử chỉ vẫn chạy) nên phải với xuống
/// `UINavigationController.interactivePopGestureRecognizer`.
private struct SwipeBackDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { Controller() }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    /// Bật/tắt theo vòng đời view: `viewWillAppear` để đè lên thiết lập mà `NavigationStack`
    /// áp lại mỗi lần đẩy màn, `viewWillDisappear` để TRẢ cử chỉ về cho các màn khác — quên
    /// trả là cả app mất vuốt-back.
    private final class Controller: UIViewController {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}

extension View {
    /// Chặn vuốt-cạnh-màn để lùi ở màn này — dùng khi lùi lại là sai luồng, vd quét QR xong
    /// vào màn chuyển tiền thì vuốt về màn quét vừa vô nghĩa vừa lệch với nút back (nút đó
    /// đóng cả luồng).
    func disablesSwipeBack() -> some View {
        background(SwipeBackDisabler().frame(width: 0, height: 0))
    }

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
