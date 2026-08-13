//
//  DismissKeyboardOnTap.swift
//  nano ewallet
//
//  Chạm ra vùng trống bất kỳ -> ẩn bàn phím. Thay cho thanh toolbar 3 nút trước đây:
//  bàn phím số của iOS không có phím Return nên cần một cách thoát, và đây là cử chỉ
//  người dùng iOS đã quen sẵn (không tốn thêm dải màn hình như toolbar).
//

import SwiftUI
import UIKit

/// Gắn 1 tap gesture ở tầng `UIWindow` để mọi màn đều có sẵn, khỏi phải nhớ thêm
/// modifier ở từng view.
///
/// Hai cờ quan trọng:
/// - `cancelsTouchesInView = false`: tap vẫn đi tiếp xuống view bên dưới, nên nút/
///   link/ô nhập hoạt động y như cũ — gesture này chỉ "nghe ké".
/// - `shouldRecognizeSimultaneouslyWith = true`: không tranh chấp với gesture của
///   ScrollView/Button.
final class KeyboardDismissInstaller: NSObject, UIGestureRecognizerDelegate {

    static let shared = KeyboardDismissInstaller()
    private override init() {}

    private weak var installedWindow: UIWindow?

    func installIfNeeded() {
        guard installedWindow == nil else { return }
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        guard let window else { return }

        let tap = UITapGestureRecognizer(target: window, action: #selector(UIView.endEditing))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
        installedWindow = window
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

extension View {
    /// Gọi 1 lần ở view gốc của app.
    func dismissesKeyboardOnTapOutside() -> some View {
        onAppear { KeyboardDismissInstaller.shared.installIfNeeded() }
    }
}
