//
//  TopSafeAreaInNavigationStack.swift
//  nano ewallet
//
//  Trả lại safe area TRÊN cho màn nằm trong `NavigationStack` của tab.
//
//  Bối cảnh: `MainTabView` phải mở `ignoresSafeArea(.container, edges: [.top, .bottom])` cho
//  `TabView`, vì `TabView` kiểu page KẸP từng trang vào vùng an toàn — không mở thì nền của màn
//  không tràn lên status bar được (đo trên iOS 16.0 và 26.5: bỏ `TabView` ra thì nền tràn, để
//  vào thì không, còn `NavigationStack` thì vô can).
//
//  Nhưng mở đỉnh ra thì SwiftUI xoá safe area trên cho CẢ subtree, nên trên iOS 16→18.x mọi màn
//  trong `NavigationStack` nhận top inset = 0 và header trôi lên dưới đồng hồ. Từ iOS 26 Apple
//  đổi hành vi: `NavigationStack` báo lại đúng số thật.
//
//  Cách sửa: hỏi UIKit xem safe area của subtree CÓ bị xoá hay không, rồi chỉ bù khi cần.
//  `nav.view.safeAreaInsets.top` là mốc BẤT BIẾN cho việc đó — nó KHÔNG phản ánh phần bù mình
//  thêm vào (đã thử: đặt `additionalSafeAreaInsets` 220 mà đọc lại vẫn ra 0). Nhờ vậy không có
//  vòng "đo rồi sửa chính mình" — thứ từng làm màn nháy liên tục.
//
//  Đo được: iOS 16.0 đặt đúng 1 lần rồi dừng, iOS 26.5 không cần đặt lần nào; cả hai đều cho
//  nền tràn lên status bar và header nằm dưới đồng hồ.
//

import SwiftUI
import UIKit

extension View {
    /// Dùng cho màn nằm trong `NavigationStack` của tab (Home và các màn push từ Home/Cá nhân).
    ///
    /// KHÔNG dùng cho màn tự quản safe area trên — `SettingsView` gốc tự
    /// `ignoresSafeArea(edges: .top)` rồi tự cộng `topSafeAreaInset` vào banner để banner tràn
    /// lên; thêm cái này nữa là cộng hai lần.
    func restoresTopSafeArea() -> some View {
        modifier(TopSafeAreaRestorer())
    }
}

private struct TopSafeAreaRestorer: ViewModifier {
    @State private var missing: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: missing)
            }
            // Đặt ở `background` để không chen vào layout của màn — view này 0x0, chỉ để với
            // xuống UIKit đọc mốc.
            .background(NavTopInsetProbe(missing: $missing).frame(width: 0, height: 0))
    }
}

/// Đọc mốc ở tầng UIKit: safe area trên của `NavigationStack` có bị SwiftUI xoá hay không.
private struct NavTopInsetProbe: UIViewControllerRepresentable {
    @Binding var missing: CGFloat

    func makeUIViewController(context: Context) -> UIViewController { Probe(binding: $missing) }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        (uiViewController as? Probe)?.binding = $missing
    }

    final class Probe: UIViewController {
        var binding: Binding<CGFloat>

        init(binding: Binding<CGFloat>) {
            self.binding = binding
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) chưa dùng") }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            update()
        }

        override func viewSafeAreaInsetsDidChange() {
            super.viewSafeAreaInsetsDidChange()
            update()
        }

        private func update() {
            guard let nav = navigationController, let window = view.window else { return }
            // `navTop == 0` = SwiftUI đã xoá safe area của subtree (iOS 16→18.x) -> phải bù.
            // `navTop > 0`  = UIKit đang báo đúng số thật (iOS 26) -> không bù gì.
            let navTop = nav.view.safeAreaInsets.top
            let needed: CGFloat = navTop == 0 ? window.safeAreaInsets.top : 0
            guard abs(binding.wrappedValue - needed) > 0.5 else { return }
            // Ghi state NGOÀI vòng layout: ghi ngay trong `viewDidLayoutSubviews` là sửa state
            // giữa lúc SwiftUI đang dựng view — hành vi không định nghĩa.
            let binding = binding
            DispatchQueue.main.async { binding.wrappedValue = needed }
        }
    }
}
