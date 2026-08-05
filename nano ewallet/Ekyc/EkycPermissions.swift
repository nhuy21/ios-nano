//
//  EkycPermissions.swift
//  nano ewallet
//
//  Kiểm tra quyền/khả năng TRƯỚC khi mở SDK CmcEkyc — bắt buộc phải làm ở tầng app, SDK
//  không tự xử lý đúng khi quyền còn ở trạng thái .notDetermined.
//
//  Chỉ camera và NFC: SDK không dùng micro (liveness của iProov là passive, không ghi âm)
//  cũng không đọc thư viện ảnh (luồng này chỉ chụp mới), nên KHÔNG xin hai quyền đó —
//  hỏi quyền không dùng tới chỉ làm người dùng nghi ngại.
//
//  Bối cảnh: lần đầu bấm "Bắt đầu xác thực" (chưa từng cấp quyền camera), app CRASH ngay
//  khi SDK cố mở camera. Mở lại app lần sau (quyền đã Allow/Deny từ dialog hệ thống) thì
//  chạy bình thường — dấu hiệu kinh điển của race condition: SDK gọi thẳng AVCaptureSession
//  trong lúc quyền còn .notDetermined (dialog hệ thống đang hiện/chưa có quyết định), thay
//  vì đợi callback của `requestAccess` xong rồi mới truy cập camera. Đây là lỗi BÊN TRONG
//  binary SDK đã biên dịch sẵn, app không sửa được code đó — chỉ có thể tránh né bằng cách
//  đảm bảo quyền đã Ở TRẠNG THÁI XÁC ĐỊNH (authorized/denied) trước khi gọi SDK, xoá hẳn
//  khoảng hở .notDetermined mà SDK xử lý sai.
//

import AVFoundation
import CoreNFC

enum EkycPermissions {
    /// Đảm bảo quyền camera đã được QUYẾT ĐỊNH (không còn `.notDetermined`) trước khi mở SDK.
    /// Trả `true` nếu được cấp quyền, `false` nếu từ chối — gọi nơi hiển thị hướng dẫn vào
    /// Cài đặt iOS thay vì mở SDK (SDK cũng sẽ crash/lỗi nếu cố mở lúc bị từ chối).
    static func ensureCameraAuthorized() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            // PHẢI đợi đúng callback này xong (await) rồi mới cho phép mở SDK — gọi
            // `requestAccess` xong bỏ qua kết quả, không đợi, là chính xác cách gây ra race
            // condition đang muốn tránh.
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// Máy có đọc được chip NFC không.
    ///
    /// KHÔNG có API xin quyền NFC lúc chạy — iOS tự hiện tấm che khi session mở, người dùng
    /// không bật/tắt được như camera. Thứ duy nhất kiểm được trước là PHẦN CỨNG có hỗ trợ
    /// hay không (iPhone 6 và cũ hơn, hoặc iPad, đều không đọc được).
    ///
    /// Kiểm để báo sớm ở màn hướng dẫn: luồng `.nfcEkyc` bắt buộc đọc chip, vào tới bước áp
    /// thẻ mới phát hiện máy không hỗ trợ thì người dùng đã chụp xong CCCD và quét mặt.
    static var isNfcAvailable: Bool {
        NFCTagReaderSession.readingAvailable
    }
}
