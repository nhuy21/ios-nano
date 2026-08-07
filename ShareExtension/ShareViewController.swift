//
//  ShareViewController.swift
//  ShareExtension
//
//  Mirror ShareReceiverActivity.kt — nhận ảnh chia sẻ từ app khác (chụp màn hình tin nhắn
//  chuyển khoản, ảnh mã QR) để app chính bóc tách.
//
//  KHÁC Android ở bước cuối: extension KHÔNG tự mở được app chính. iOS 18+ chặn hẳn việc
//  này (`UIApplication` không dùng được trong extension, và mẹo lần theo responder chain
//  gọi `openURL:` đã bị vô hiệu — Apple cố ý cấm, chỉ Widget mới mở được app qua App
//  Intents). Nên ở đây chỉ LƯU ảnh rồi báo người dùng tự mở app; app chính thấy ảnh đang
//  chờ là bóc tách ngay.
//

import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

    private let messageLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpUI()
        handleSharedImage()
    }

    private func setUpUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.35)

        let card = UIView()
        card.backgroundColor = .systemBackground
        card.layer.cornerRadius = 20
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        messageLabel.text = "Đang nhận ảnh..."
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.font = .systemFont(ofSize: 15, weight: .medium)
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            card.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),

            messageLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            messageLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),
            messageLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
        ])
    }

    private func handleSharedImage() {
        // Duyệt HẾT các inputItem chứ không chỉ cái đầu: một số app đính kèm thêm item phụ
        // (text/URL kèm ảnh) và ảnh có thể không nằm ở item đầu tiên.
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .compactMap(\.attachments)
            .flatMap { $0 }
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }) else {
            finish(message: "Không đọc được ảnh vừa chia sẻ.")
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
                self?.finish(message: "Không lưu được ảnh, vui lòng thử lại.")
                return
            }
            self?.finish(message: "Đã nhận ảnh. Mở Ví nano để tiếp tục chuyển tiền.")
        }
    }

    /// Hiện thông báo rồi tự đóng: không có nút "Mở app" vì extension không mở được app
    /// chính trên iOS 18+ — có nút mà bấm không ăn còn khó hiểu hơn.
    private func finish(message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.messageLabel.text = message
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                self.extensionContext?.completeRequest(returningItems: nil)
            }
        }
    }
}
