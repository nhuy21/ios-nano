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
            // Báo màu này lên `MainTabView` để nó tô luôn dải status bar phía sau `TabView`.
            // Trong tab, vùng status bar không thuộc khung của trang nên `ignoresSafeArea` ở
            // trên chỉ với tới mép safe area — xem `ScreenTopBackdropKey`.
            .screenTopBackdrop(color)
    }

    /// Chạm vào là nhún nhẹ rồi bật lại — phản hồi chung cho mọi thứ bấm được trong app.
    ///
    /// Đặt SAU các modifier tạo hình (`background`/`clipShape`/`overlay`) để cả khối nhún
    /// cùng nhau; đặt trước chúng thì chỉ phần nội dung co lại còn nền đứng yên. Ngược với
    /// Compose — bên đó `pressable` phải đứng TRƯỚC `clip/background`, vì thứ tự modifier
    /// hai bên chạy ngược chiều nhau.
    ///
    /// - Parameters:
    ///   - enabled: `false` thì không nhún và không nhận chạm.
    ///   - scale: độ co khi nhấn.
    ///   - action: việc cần làm khi nhả tay trong vùng.
    func pressable(
        enabled: Bool = true,
        scale: CGFloat = 0.94,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) { self }
            .buttonStyle(PressableButtonStyle(scale: scale))
            .disabled(!enabled)
    }

    /// Bấm được nhưng KHÔNG nhún — cho những chỗ mà co lại là sai: nút mic đang nghe (đã có
    /// hiệu ứng sóng riêng), lớp phủ trên camera/WebView, và các vùng chặn chạm của sheet.
    func tappable(enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) { self }
            .buttonStyle(.plain)
            .disabled(!enabled)
    }
}

extension UIApplication {
    /// Chiều cao vùng an toàn phía trên (status bar / Dynamic Island) của cửa sổ đang hiện.
    ///
    /// Cần khi một màn tự bỏ qua safe area trên (`ignoresSafeArea(edges: .top)`) rồi phải tự
    /// bù lại khoảng đó cho nội dung — lúc ấy không còn cách nào lấy được số này từ layout.
    /// Đọc từ window thật chứ không ghim hằng số: tai thỏ, Dynamic Island và máy không tai
    /// mỗi loại một chiều cao khác nhau. `UIScreen.main` đã bị khai tử từ iOS 26 nên đi qua
    /// scene.
    ///
    /// Quét MỌI window của mọi scene rồi lấy số lớn nhất, thay vì chỉ hỏi key window: lúc
    /// `body` dựng lần đầu, key window có thể chưa layout xong và trả 0. Số 0 đó lọt qua mọi
    /// `??` (nó không phải `nil`) nên vùng bù cao 0pt và header đè thẳng lên tai thỏ — chỉ
    /// hiện trên một số máy vì thứ tự dựng window không giống nhau giữa các đời.
    ///
    /// Không còn window nào cho số dương thì đoán theo chiều cao màn: 47pt cho Dynamic
    /// Island, 44pt cho tai thỏ. Đoán 47 cho máy tai thỏ là dôi 3pt, nhìn ra ngay.
    var topSafeAreaInset: CGFloat {
        let measured = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .map(\.safeAreaInsets.top)
            .max() ?? 0
        if measured > 0 { return measured }

        // Máy có tai thỏ/Dynamic Island đều cao >= 812pt; nhỏ hơn là máy có nút Home,
        // status bar 20pt. Lấy chiều cao từ window (không dùng `UIScreen.main` lẫn
        // `UIWindowScene.screen` — cả hai đều đã bị khai tử ở iOS 26).
        let height = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .map(\.bounds.height)
            .max() ?? 0
        switch height {
        case 0: return 47          // chưa có window nào — đoán đời mới
        case ..<812: return 20     // nút Home
        case ..<845: return 44     // X / XS / 11 Pro / 12 mini / 13 mini
        default: return 47         // Dynamic Island và các đời sau
        }
    }
}

/// Nhún khi nhấn, dùng qua `View.pressable`.
///
/// Hai chiều dùng animation KHÁC nhau, cố ý: nhấn xuống phải bắt kịp ngón tay nên đi thẳng
/// và ngắn (70ms), còn nhả ra mới nảy. Dùng chung một spring cho cả hai chiều thì cú chạm
/// nhanh (~120ms) chỉ kịp co được vài phần trăm — nhìn như không có hiệu ứng gì.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // `scaleEffect` chỉ ảnh hưởng lúc VẼ, không đo lại layout, nên phần tử bên cạnh
            // không bị xê dịch theo.
            .scaleEffect(configuration.isPressed ? scale : 1)
            // Gom thành một lớp trước khi thu nhỏ, để bóng đổ (gắn ở NGOÀI style, như
            // `PrimaryButton.primaryButtonShadow`) co theo nút thay vì đứng nguyên cỡ cũ
            // rồi thò ra ngoài mép lúc nhấn.
            .compositingGroup()
            .animation(
                configuration.isPressed
                    ? .easeOut(duration: 0.07)
                    : .interpolatingSpring(stiffness: 320, damping: 18),
                value: configuration.isPressed
            )
            // Giữ nguyên vùng chạm là cả khung kể cả chỗ trong suốt — thiếu dòng này thì
            // khoảng đệm quanh icon không ăn chạm, nút nhỏ trở nên khó bấm.
            .contentShape(Rectangle())
    }
}
