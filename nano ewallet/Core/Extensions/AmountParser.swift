//
//  AmountParser.swift
//  nano ewallet
//
//  Mirror AmountParser.kt — bóc SỐ TIỀN (đồng) từ đoạn text tự do, dùng cho OneTouch
//  khi nhận diện chuyển VÍ (đường ngân hàng đã có backend bóc số; ví thì tự bóc ở
//  client), và để lấy số tiền từ CHỮ trong ảnh khi mã QR là QR tĩnh (không nhúng số
//  tiền — xem `ocrAmount(from:)`).
//
//  Thứ tự mẫu KHÔNG được đổi: ưu tiên các mẫu CÓ ĐƠN VỊ (k/nghìn/triệu/đ) để không
//  nhầm số ví — vốn là dãy số dài không đơn vị — thành số tiền.
//

import Foundation

enum AmountParser {

    /// Trần số tiền chấp nhận được. Vượt ngưỡng này gần như chắc chắn là bóc nhầm một dãy
    /// số khác (số tài khoản, mã giao dịch) chứ không phải tiền người dùng định chuyển.
    private static let maxAmount: Int64 = 999_999_999

    /// Các bậc đơn vị, kể cả tiếng lóng hay gặp trong tin nhắn.
    /// Thứ tự trong chuỗi này CÓ nghĩa: regex thay phiên lấy nhánh khớp ĐẦU TIÊN, nên bậc
    /// dài phải đứng trước bậc là tiền tố của nó ("triệu" trước "tr", không thì "triệu" bị
    /// cắt thành "tr" + thừa chữ "iệu").
    private static let units = "nghìn|ngàn|triệu|tr|tỷ|tỉ|tỏi|củ|lốp|chai|k"

    private static func unitMultiplier(_ unit: String) -> Int64 {
        switch unit {
        case "k", "nghìn", "ngàn": return 1_000
        case "lốp", "chai": return 100_000
        case "tr", "triệu", "củ": return 1_000_000
        case "tỷ", "tỉ", "tỏi": return 1_000_000_000
        default: return 1
        }
    }

    /// Số viết bằng chữ đứng ngay trước bậc: "hai lốp", "ba củ". Chỉ nhận MỘT từ — chat ít
    /// khi viết số dài bằng chữ, còn dạng nhiều từ ("hai trăm nghìn") vẫn vào được nhánh
    /// nhóm-nghìn/đơn-vị bên dưới.
    private static let wordDigits: [String: Int64] = [
        "một": 1, "hai": 2, "ba": 3, "bốn": 4, "tư": 4, "năm": 5,
        "sáu": 6, "bảy": 7, "tám": 8, "chín": 9, "mười": 10,
    ]

    /// Một số tiền bóc được cùng VÙNG chữ đã sinh ra nó — để mẫu sau không bóc lại cùng chỗ.
    private struct Hit {
        let range: NSRange
        let value: Int64
    }

    // MARK: - API

    /// MỌI số tiền bóc được trong text, theo thứ tự ưu tiên mẫu, đã loại trùng giá trị.
    ///
    /// Dùng khi cần biết text có MƠ HỒ về số tiền hay không: ảnh chụp đoạn chat thường có
    /// nhiều số tiền ("chuyển 20k" rồi "còn 500k nữa"), lúc đó điền số nào cũng là đoán hộ.
    static func parseVndCandidates(_ text: String) -> [Int64] {
        var seen = Set<Int64>()
        return moneyHits(in: text.lowercased())
            .map(\.value)
            .filter { seen.insert($0).inserted }
    }

    /// "gửi 500k" -> 500000, "1tr5"/"1,5tr" -> 1500000, "500.000đ" -> 500000.
    /// `nil` khi không bóc được số tiền rõ ràng.
    static func parseVnd(from text: String) -> Int64? {
        parseVndCandidates(text).first
    }

    /// Số tiền suy từ chữ trong ảnh — CHỈ trả về khi chắc chắn.
    ///
    /// Mơ hồ thì để trống, vì đây là phỏng đoán chứ không phải số nhúng trong mã QR:
    ///  - Ảnh có từ 2 số tiền khác nhau (đoạn chat nhiều lượt) — điền cái nào cũng là đoán.
    ///  - Không bóc được số nào.
    ///  - Mọi giá trị đều vượt trần — gần như chắc chắn là bóc nhầm dãy số khác.
    ///
    /// Trong app tiền thì để trống cho người dùng tự gõ còn hơn điền sai một cách lặng lẽ.
    static func ocrAmount(from text: String) -> Int64? {
        let valid = parseVndCandidates(text).filter { $0 > 0 && $0 <= maxAmount }
        return valid.count == 1 ? valid[0] : nil
    }

    /// Mọi dãy 6–20 chữ số trong text, bỏ trùng, giữ nguyên thứ tự xuất hiện.
    /// Dùng để dò số ví khi backend không bóc được ngân hàng.
    static func numberCandidates(in text: String) -> [String] {
        var seen = Set<String>()
        return allMatches(#"[0-9]{6,20}"#, in: text).filter { seen.insert($0).inserted }
    }

    /// Text chỉ gồm 6–20 chữ số — dấu hiệu người dùng dán mỗi số ví.
    static func isBareNumber(_ text: String) -> Bool {
        firstMatch(#"^[0-9]{6,20}$"#, in: text) != nil
    }

    // MARK: - Bóc số tiền

    /// Các mẫu XẾP THEO ĐỘ ƯU TIÊN — mẫu đặc thù trước mẫu tổng quát.
    ///
    /// Mỗi mẫu quét HẾT text (không dừng ở lần khớp đầu) vì `parseVndCandidates` cần biết
    /// text có nhiều số tiền khác nhau hay không.
    private static func moneyHits(in text: String) -> [Hit] {
        let ns = text as NSString
        var hits: [Hit] = []

        func collect(_ pattern: String, _ value: (NSTextCheckingResult) -> Int64?) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                // Vùng đã bị mẫu ưu tiên cao hơn bóc rồi thì bỏ qua: "1tr5" phải là 1.500.000
                // (mẫu 2), đừng để mẫu 4 bóc thêm "1tr" = 1.000.000 từ chính chỗ đó rồi tưởng
                // là hai số tiền khác nhau — ca rõ ràng lại bị coi là mơ hồ.
                let overlaps = hits.contains { hit in
                    hit.range.location <= match.range.location + match.range.length - 1
                        && match.range.location <= hit.range.location + hit.range.length - 1
                }
                if overlaps { continue }
                guard let v = value(match), v > 0 else { continue }
                hits.append(Hit(range: match.range, value: v))
            }
        }

        /// Chuỗi ngay SAU vùng khớp — để xét "rưỡi" dính đuôi.
        func tail(after match: NSTextCheckingResult) -> String {
            let end = match.range.location + match.range.length
            guard end < ns.length else { return "" }
            return ns.substring(from: end)
        }

        func group(_ match: NSTextCheckingResult, _ index: Int) -> String? {
            let range = match.range(at: index)
            guard range.location != NSNotFound else { return nil }
            return ns.substring(with: range)
        }

        // 1) "nửa <bậc>": "nửa củ" = 500.000, "nửa lốp" = 50.000 ("nữa" là biến thể chính tả).
        collect("(?:nửa|nữa)\\s*(\(units))(?!\\p{L})") { m in
            group(m, 1).map { unitMultiplier($0) / 2 }
        }

        // 2) "1tr5" = 1 triệu 5 = 1.500.000. Phải xét TRƯỚC nhánh tổng quát, không thì mất "5".
        collect("(\\d+)\\s*(?:triệu|tr|củ)\\s*(\\d)(?!\\d)") { m in
            guard let whole = group(m, 1).flatMap(Int64.init),
                  let digit = group(m, 2).flatMap(Int64.init) else { return nil }
            return whole * 1_000_000 + digit * 100_000
        }

        // 3) Số THẬP PHÂN + bậc: "1,5tr", "1.5 triệu", "2,5 lốp"
        collect("(\\d+)[.,](\\d+)\\s*(\(units))(?!\\p{L})") { m in
            guard let whole = group(m, 1).flatMap(Int64.init),
                  let frac = group(m, 2),
                  let fracValue = Int64(frac),
                  let unit = group(m, 3) else { return nil }
            let mult = unitMultiplier(unit)
            var divisor: Int64 = 1
            for _ in 0..<frac.count { divisor *= 10 }
            let v = whole * mult + fracValue * (mult / divisor)
            return v > 0 ? v + halfIfRuoi(tail(after: m), mult) : nil
        }

        // 4) Số NGUYÊN + bậc (+ "rưỡi"): "500k", "2 lốp", "1 củ", "2 lốp rưỡi", "1 tỏi"
        collect("(\\d+)\\s*(\(units))(?!\\p{L})") { m in
            guard let whole = group(m, 1).flatMap(Int64.init),
                  let unit = group(m, 2) else { return nil }
            let mult = unitMultiplier(unit)
            let v = whole * mult
            return v > 0 ? v + halfIfRuoi(tail(after: m), mult) : nil
        }

        // 5) Số BẰNG CHỮ + bậc (+ "rưỡi"): "hai lốp", "ba củ", "hai lốp rưỡi"
        collect("(\(wordDigits.keys.joined(separator: "|")))\\s*(\(units))(?!\\p{L})") { m in
            guard let word = group(m, 1), let digit = wordDigits[word],
                  let unit = group(m, 2) else { return nil }
            let mult = unitMultiplier(unit)
            let v = digit * mult
            return v > 0 ? v + halfIfRuoi(tail(after: m), mult) : nil
        }

        // 6) Nhóm nghìn bằng dấu chấm (kèm/không kèm "đ"): "500.000", "1.500.000đ"
        //
        // `(?<![\d.])` chặn cắt GIỮA một dãy số: số tài khoản viết "0123.456.789" (nhóm đầu 4
        // chữ số) mà không có ranh giới này thì khớp từ "456.789" -> điền 456.789đ lấy từ một
        // số TÀI KHOẢN. Phải chặn cả DẤU CHẤM liền trước chứ không chỉ chữ số, vì chỗ khớp sai
        // bắt đầu ngay sau dấu chấm của nhóm trước. Đây là mẫu duy nhất không đòi đơn vị tiền
        // nên cũng là mẫu dễ nhầm nhất.
        collect("(?<![\\d.])(\\d{1,3}(?:\\.\\d{3})+)\\s*đ?") { m in
            // Tách hai bước: `replacingOccurrences` trả `String` KHÔNG optional, nên nối
            // `.flatMap` vào sẽ bị hiểu là duyệt từng ký tự của chuỗi thay vì gỡ optional.
            guard let raw = group(m, 1) else { return nil }
            return Int64(raw.replacingOccurrences(of: ".", with: ""))
        }

        // 7) Số + "đ": "200000đ" — cũng chặn cắt giữa dãy ("0123.456.789đ" không được ra 789).
        collect("(?<![\\d.])(\\d+)\\s*đ") { m in
            group(m, 1).flatMap(Int64.init)
        }

        return hits
    }

    /// "rưỡi" (kể cả biến thể "rưởi") dính ngay sau bậc -> cộng thêm NỬA bậc đó.
    private static func halfIfRuoi(_ rest: String, _ multiplier: Int64) -> Int64 {
        firstMatch("^\\s*(?:rưỡi|rưởi)(?!\\p{L})", in: rest) != nil ? multiplier / 2 : 0
    }

    // MARK: - Regex helper

    /// Capture group của lần khớp ĐẦU TIÊN. Phần tử 0 là toàn bộ chuỗi khớp; group
    /// không tham gia khớp trả `nil` (tương ứng chuỗi rỗng của `groupValues` bên Kotlin).
    private static func firstMatch(_ pattern: String, in text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }

        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func allMatches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }
}
