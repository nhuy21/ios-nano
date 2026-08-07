//
//  ShareViewController.swift
//  ShareExtension
//
//  Mirror ShareReceiverActivity.kt — nhận ảnh chia sẻ từ app khác (chụp màn hình tin nhắn
//  chuyển khoản, ảnh mã QR) rồi mở app chính để bóc tách.
//
//  KHÔNG có giao diện: người dùng đã chọn đúng ảnh ở share sheet rồi, hiện thêm một màn
//  xác nhận nữa là thừa một bước. Lưu ảnh xong là đóng và mở app luôn.
//

import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Nền trong suốt: extension này không vẽ gì, chớp một khung trắng lên rồi tắt sẽ
        // nhìn như app lỗi.
        view.backgroundColor = .clear
        handleSharedImage()
    }

    private func handleSharedImage() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first(where: {
                  $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
              }) else {
            finish(openApp: false)
            return
        }

        provider.loadItem(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
            // Nguồn ảnh không thống nhất: app này gửi `UIImage`, app kia gửi `URL` tới file,
            // app khác nữa gửi `Data` — nhận cả ba, thiếu nhánh nào là chia sẻ từ app đó
            // im lặng không ăn.
            let image: UIImage? = {
                if let image = data as? UIImage { return image }
                if let url = data as? URL, let fileData = try? Data(contentsOf: url) {
                    return UIImage(data: fileData)
                }
                if let raw = data as? Data { return UIImage(data: raw) }
                return nil
            }()

            guard let image, SharedImageStore.save(image) else {
                self?.finish(openApp: false)
                return
            }
            self?.finish(openApp: true)
        }
    }

    private func finish(openApp: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if openApp { self.openHostApp() }
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    /// Mở app chính bằng custom scheme. Extension không được gọi `UIApplication.shared` nên
    /// phải lần theo chuỗi `responder` tìm đối tượng có `openURL:` — cách duy nhất còn dùng
    /// được trong app extension.
    private func openHostApp() {
        guard let url = URL(string: "nanowallet://onetouch") else { return }
        var responder: UIResponder? = self
        let selector = sel_registerName("openURL:")
        while let current = responder {
            if current.responds(to: selector) {
                _ = current.perform(selector, with: url)
                return
            }
            responder = current.next
        }
    }
}
