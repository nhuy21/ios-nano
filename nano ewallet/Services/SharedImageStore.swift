//
//  SharedImageStore.swift
//  nano ewallet
//
//  Mirror SharedImageStore.kt — cầu nối ảnh từ Share Extension sang app chính.
//
//  Extension chạy trong TIẾN TRÌNH RIÊNG, không dùng chung bộ nhớ với app, nên phải ghi
//  ảnh ra thư mục App Group rồi app chính đọc lại. Không giữ `NSItemProvider` của app gửi:
//  quyền đọc nó chỉ sống theo phiên extension, mà luồng này có thể trễ rất lâu (chưa đăng
//  nhập lúc chia sẻ -> phải qua đăng nhập/OTP mới tới Home).
//
//  File này PHẢI thuộc CẢ HAI target (app + Share Extension).
//

import Foundation
import UIKit

enum SharedImageStore {
    /// Phải khớp App Group đã bật ở cả hai target trong Signing & Capabilities.
    static let appGroupId = "group.vn.casso.nano"

    private static let folderName = "SharedImages"
    /// Ảnh cũ hơn mốc này coi như người dùng đã bỏ quên — mirror hạn 1 giờ bên Android.
    private static let maxAge: TimeInterval = 60 * 60

    private static var folderUrl: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else { return nil }
        let folder = container.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    /// Extension gọi: chép ảnh vào App Group. Trả `false` khi chưa bật App Group.
    @discardableResult
    static func save(_ image: UIImage) -> Bool {
        guard let folder = folderUrl,
              let data = image.jpegData(compressionQuality: 0.9) else { return false }
        // Ghi đè một tên cố định: chỉ cần ảnh MỚI NHẤT, giữ nhiều file chỉ tốn chỗ rồi
        // phải tự dọn.
        let url = folder.appendingPathComponent("pending.jpg")
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// Có ảnh đang chờ và còn hạn không — CHỈ hỏi, không đọc cũng không xoá.
    ///
    /// Dùng để màn quét QR mặc định nhường chỗ: chia sẻ ảnh vào app tức là đã có người nhận,
    /// mở QR bắt quét thêm mã nữa là sai ý người dùng.
    static var hasPending: Bool {
        guard let folder = folderUrl else { return false }
        let url = folder.appendingPathComponent("pending.jpg")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(modified) <= maxAge
    }

    /// App chính gọi: lấy ảnh đang chờ (nếu còn hạn) rồi XOÁ ngay — mỗi lần chia sẻ chỉ xử
    /// lý một lần, không để mở app lần sau lại bóc tách lại ảnh cũ.
    static func consumePending() -> UIImage? {
        guard let folder = folderUrl else { return nil }
        let url = folder.appendingPathComponent("pending.jpg")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date else { return nil }

        defer { try? FileManager.default.removeItem(at: url) }

        guard Date().timeIntervalSince(modified) <= maxAge,
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}
