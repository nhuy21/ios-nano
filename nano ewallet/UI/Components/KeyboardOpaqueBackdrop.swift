//
//  KeyboardOpaqueBackdrop.swift
//  nano ewallet
//
//  Bàn phím iOS 26 dùng nền kính mờ, nên nội dung sặc sỡ nằm sau nó hắt màu xuyên
//  qua — rõ nhất là PrimaryButton xanh làm cả hàng phím bị ám xanh.
//
//  Không có API nào đổi được độ trong của bàn phím hệ thống. Cách xử lý: chèn một
//  lớp TRẮNG ĐẶC đúng vùng bàn phím chiếm chỗ. Bàn phím nằm ở window riêng phía
//  trên nên nó sẽ lấy mẫu blur từ lớp trắng này -> nhìn sạch, không ám màu.
//
//  Làm bằng UIKit ở tầng window thay vì overlay SwiftUI: khi bàn phím hiện,
//  SwiftUI thu safe area đáy lại đúng bằng chiều cao bàn phím, nên overlay canh
//  đáy sẽ nằm PHÍA TRÊN bàn phím và che nhầm nội dung.
//

import SwiftUI
import UIKit

@MainActor
final class KeyboardBackdropInstaller {

    static let shared = KeyboardBackdropInstaller()
    private init() {}

    private weak var window: UIWindow?
    private var backdrop: UIView?

    func installIfNeeded() {
        guard backdrop == nil else { return }
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        guard let keyWindow else { return }

        let view = UIView()
        view.backgroundColor = .white
        // Không nhận chạm: vùng này bàn phím che hết rồi, và phải để thao tác
        // vuốt-để-ẩn của ScrollView đi xuyên qua.
        view.isUserInteractionEnabled = false
        view.isHidden = true
        keyWindow.addSubview(view)

        window = keyWindow
        backdrop = view
        observeKeyboard()
    }

    // MARK: - Private

    private func observeKeyboard() {
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(keyboardWillChangeFrame),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil
        )
        center.addObserver(
            self, selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification, object: nil
        )
    }

    @objc private func keyboardWillChangeFrame(_ note: Notification) {
        guard let window, let backdrop,
              let screenFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        else { return }

        // Frame trong notification là toạ độ màn hình -> đổi về toạ độ window.
        let frame = window.convert(screenFrame, from: nil)
        // Kéo dài xuống hết đáy phòng khi bàn phím không sát mép (chia đôi màn, v.v.).
        let covered = CGRect(
            x: frame.minX,
            y: frame.minY,
            width: frame.width,
            height: max(frame.height, window.bounds.maxY - frame.minY)
        )

        backdrop.frame = covered
        backdrop.isHidden = false
        // Giữ luôn ở trên cùng của window: SwiftUI có thể thêm view mới khi điều hướng.
        window.bringSubviewToFront(backdrop)
    }

    @objc private func keyboardWillHide(_ note: Notification) {
        backdrop?.isHidden = true
    }
}

extension View {
    /// Gọi 1 lần ở view gốc của app.
    func opaqueKeyboardBackdrop() -> some View {
        onAppear { KeyboardBackdropInstaller.shared.installIfNeeded() }
    }
}
