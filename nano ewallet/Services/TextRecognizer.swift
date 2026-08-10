//
//  TextRecognizer.swift
//  nano ewallet
//
//  OCR ảnh — dùng cho OneTouch khi ảnh dán KHÔNG chứa mã QR (vd ảnh chụp màn hình
//  tin nhắn chuyển khoản). Dùng Vision của iOS thay ML Kit bên Android.
//

import Foundation
import Vision
import UIKit

enum TextRecognizer {

    /// Đọc toàn bộ chữ trong ảnh, nối các dòng bằng xuống dòng. Chuỗi rỗng nghĩa là
    /// không đọc được gì.
    static func recognizeText(in image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        let raw: String = await withCheckedContinuation { continuation in
            // `VNRecognizeTextRequest`/`VNImageRequestHandler` là non-Sendable nên phải
            // tạo NGAY TRONG closure của `async`, không capture từ ngoài vào — capture
            // sẽ thành lỗi ở Swift 6 (`@Sendable` closure không nhận non-Sendable).
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, _ in
                    let observations = request.results as? [VNRecognizedTextObservation] ?? []
                    // SẮP XẾP theo toạ độ trước khi ghép: Vision không cam kết trả về theo
                    // thứ tự đọc, mà tin nhắn chuyển khoản thì thứ tự dòng quyết định nghĩa
                    // (số tài khoản ở dòng này, tên ngân hàng ở dòng kia). Trả lộn xộn thì
                    // backend ghép nhầm ngân hàng với số tài khoản khác dòng.
                    // `boundingBox` gốc toạ độ ở ĐÁY ảnh nên y lớn = dòng trên.
                    let lines = observations
                        .sorted { lhs, rhs in
                            let dy = lhs.boundingBox.origin.y - rhs.boundingBox.origin.y
                            // Cùng một dòng (lệch dưới 1% chiều cao) thì xếp trái sang phải.
                            if abs(dy) > 0.01 { return dy > 0 }
                            return lhs.boundingBox.origin.x < rhs.boundingBox.origin.x
                        }
                        .compactMap { $0.topCandidates(1).first?.string }
                        // Bỏ dòng chỉ ĐÚNG MỘT chữ cái đứng riêng: ảnh chụp màn hình có bàn
                        // phím ảo thì mỗi phím (Q, W, E, R, T...) là một block riêng, Vision
                        // ở mức `.accurate` đọc ra hơn hai chục "dòng" một ký tự như vậy —
                        // toàn nhiễu, không ai đặt tên ngân hàng/nội dung chuyển khoản bằng
                        // đúng 1 chữ cái. Với văn bản dài, hàng phím này chen ngay sau dòng
                        // thông tin thật, làm mô hình trích xuất phía backend nhận nhầm tín
                        // hiệu. CHỈ lọc chữ cái đơn — không đụng số ("0", "1"...) hay dòng đã
                        // có từ 2 ký tự trở lên ("Em", "10k", "Vietin"...).
                        .filter { line in
                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                            guard trimmed.count == 1, let char = trimmed.first else { return true }
                            return !char.isLetter
                        }
                    continuation.resume(returning: lines.joined(separator: "\n"))
                }
                // `accurate` vì tin nhắn CK có số tài khoản dài, nhận nhầm 1 chữ số là
                // chuyển sai người. Chậm hơn `fast` nhưng đây là thao tác một lần.
                request.recognitionLevel = .accurate
                // Ưu tiên tiếng Việt nếu máy có (Vision bổ sung dần theo bản iOS), rơi về
                // en-US cho máy chưa hỗ trợ — chữ Latin không dấu và chữ số vẫn đọc tốt.
                request.recognitionLanguages = Self.preferredLanguages
                // KHÔNG bật sửa chính tả: nó "sửa" cả dãy số tài khoản thành từ có nghĩa.
                request.usesLanguageCorrection = false

                do {
                    try VNImageRequestHandler(
                        cgImage: cgImage,
                        // Thiếu tham số này là lỗi hay gặp nhất: `cgImage` chỉ là mảng pixel
                        // thô, hướng ảnh nằm ở `UIImage.imageOrientation`. Ảnh chụp màn hình
                        // luôn `.up` nên chạy đúng, còn ảnh từ camera/thư viện thường xoay
                        // 90° — Vision đọc ảnh nằm ngang và trả về gần như không có chữ.
                        orientation: orientation,
                        options: [:]
                    ).perform([request])
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }

        return normalize(raw)
    }

    /// Ngôn ngữ nhận dạng, hỏi hệ thống lúc chạy thay vì ghim cứng: danh sách Vision hỗ trợ
    /// thay đổi theo phiên bản iOS, ghim `vi-VN` trên máy chưa có sẽ làm request hỏng hẳn.
    private static let preferredLanguages: [String] = {
        // Là method của INSTANCE, không phải của type — bản static chỉ có ở API mới (iOS 18+)
        // nên gọi kiểu đó sẽ không biên dịch được với deployment target 16.0.
        let probe = VNRecognizeTextRequest()
        probe.recognitionLevel = .accurate
        let supported = (try? probe.supportedRecognitionLanguages()) ?? []
        let vietnamese = supported.first { $0.hasPrefix("vi") }
        return [vietnamese, "en-US"].compactMap { $0 }
    }()

    // MARK: - Chuẩn hoá
    //
    // Mirror `services/OcrText.kt` (`normalizeOcrText`) — CÓ tồn tại bên Android, đã tra sai
    // đường dẫn (package cũ `com.baynet.digiflank`, đã đổi sang `vn.casso.nano`) nên trước
    // đó tưởng nhầm là không có và xoá mất bước này. Giữ nguyên vì Vision cùng có tật của
    // ML Kit: chèn khoảng trắng vào giữa một dãy số dài tuỳ font/khoảng cách chữ trong ảnh —
    // "0976505139" đọc thành "09765051 39". Backend chỉ thấy hai dãy rời, lấy dãy đầu làm số
    // tài khoản nên tra cứu hỏng, mà người dùng chỉ nhận "Tài khoản không hợp lệ" không đoán
    // được vì sao.
    //
    // NHƯNG phải chừa SỐ TIỀN: trong "bidv 7101914631 200k", số tài khoản kết thúc bằng chữ
    // số còn "200k" mở đầu bằng chữ số — nối vô điều kiện sẽ dính thành "7101914631200k",
    // hỏng cả hai. Quy tắc: không nối nếu nhóm số phía sau có ĐƠN VỊ TIỀN đi kèm, kể cả khi
    // đơn vị cách nhóm số bằng khoảng trắng ("200 nghìn", "2 tr").
    //
    // Chỉ bỏ khoảng trắng NGANG, giữ nguyên xuống dòng: hai dòng khác nhau là hai thông tin
    // khác nhau, dính vào nhau là sai nghĩa.
    private static func normalize(_ raw: String) -> String {
        guard let gapRegex = Self.digitGapRegex, let unitRegex = Self.moneyUnitRegex else {
            return raw
        }

        let ns = raw as NSString
        var result = ""
        var cursor = 0

        for match in gapRegex.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))

            let tailStart = match.range.location + match.range.length
            let tail = ns.substring(from: tailStart)
            let tailRange = NSRange(location: 0, length: (tail as NSString).length)
            let followedByMoneyUnit = unitRegex.firstMatch(in: tail, range: tailRange) != nil

            if followedByMoneyUnit {
                // Có đơn vị tiền theo sau -> đây là SỐ TIỀN, giữ nguyên khoảng trắng.
                result += ns.substring(with: match.range)
            } else {
                // Bỏ khoảng trắng, chỉ giữ nhóm chữ số phía sau.
                result += ns.substring(with: match.range(at: 1))
            }
            cursor = tailStart
        }

        result += ns.substring(from: cursor)
        return result
    }

    /// Đơn vị tiền, kèm biến thể không dấu (OCR và người dùng hay bỏ dấu).
    private static let moneyUnits =
        "nghìn|nghin|ngàn|ngan|triệu|trieu|đồng|dong|tỏi|toi|lốp|lop|củ|cu|tỷ|ty|tỉ|ti|tr|k|đ|d"

    /// Khoảng trắng ngang nằm giữa hai chữ số, bắt kèm nhóm số phía sau để còn xét đơn vị.
    private static let digitGapRegex = try? NSRegularExpression(pattern: "(?<=\\d)[ \\t]+(\\d+)")

    /// Ngay sau nhóm số thứ hai có phải đơn vị tiền không (cho phép cách bởi khoảng trắng).
    /// Dùng `(?![\\p{L}])` thay `\\b` vì `\\b` không xử lý đúng chữ "đ".
    private static let moneyUnitRegex = try? NSRegularExpression(
        pattern: "^[ \\t]*(?:\(moneyUnits))(?![\\p{L}])",
        options: [.caseInsensitive]
    )
}

extension CGImagePropertyOrientation {
    /// Đổi hướng của `UIImage` sang kiểu mà Vision/Core Image dùng.
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
