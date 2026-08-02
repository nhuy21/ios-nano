//
//  AmountParser.swift
//  nano ewallet
//
//  Mirror AmountParser.kt — bóc SỐ TIỀN (đồng) từ đoạn text tự do, dùng cho OneTouch
//  khi nhận diện chuyển VÍ (đường ngân hàng đã có backend bóc số; ví thì tự bóc ở
//  client).
//
//  Thứ tự thử KHÔNG được đổi: ưu tiên các mẫu CÓ ĐƠN VỊ (k/nghìn/triệu/đ) để không
//  nhầm số ví — vốn là dãy số dài không đơn vị — thành số tiền.
//

import Foundation

enum AmountParser {

    /// "gửi 500k" -> 500000, "1tr5"/"1,5tr" -> 1500000, "500.000đ" -> 500000.
    /// `nil` khi không bóc được số tiền rõ ràng.
    static func parseVnd(from text: String) -> Int64? {
        let lowered = text.lowercased()

        // 1) triệu THẬP PHÂN: "1,5tr", "1.5 triệu".
        //
        // CỐ Ý ĐẢO THỨ TỰ so với AmountParser.kt. Bản Kotlin để mẫu số nguyên trước, mà
        // regex lấy khớp TRÁI NHẤT nên "1,5tr" bị mẫu đó ăn mất phần "5tr" -> ra 5.000.000
        // thay vì 1.500.000. Comment trong bản Kotlin ghi rõ mẫu thập phân là để xử
        // "1,5tr" nên đây là lỗi che khuất, không phải chủ ý. Sai số tiền gấp hơn 3 lần
        // nên không bê nguyên.
        if let groups = firstMatch(#"(\d+[.,]\d+)\s*(?:tr|triệu)"#, in: lowered),
           let raw = groups[1],
           let number = Double(raw.replacingOccurrences(of: ",", with: ".")) {
            return Int64(number * 1_000_000)
        }

        // 2) triệu số nguyên: "1tr", "2 tr", "1tr5" (1 triệu 5 = 1.500.000)
        if let groups = firstMatch(#"(\d+)\s*(?:tr|triệu)\s*(\d)?"#, in: lowered),
           let wholeText = groups[1],
           let whole = Int64(wholeText) {
            var value = whole * 1_000_000
            // "tr5" -> thêm 500.000
            if let tailText = groups[2], let tail = Int64(tailText) {
                value += tail * 100_000
            }
            if value > 0 { return value }
        }

        // 3) nghìn / ngàn / k: "500k", "500 nghìn", "50 ngàn"
        if let groups = firstMatch(#"(\d+(?:[.,]\d+)?)\s*(?:k|nghìn|ngàn)\b"#, in: lowered),
           let raw = groups[1],
           let number = Double(raw.replacingOccurrences(of: ",", with: ".")) {
            return Int64(number * 1_000)
        }

        // 4) nhóm nghìn bằng dấu chấm: "500.000", "1.500.000đ"
        if let groups = firstMatch(#"(\d{1,3}(?:\.\d{3})+)\s*đ?"#, in: lowered),
           let raw = groups[1] {
            let digits = raw.replacingOccurrences(of: ".", with: "")
            if let value = Int64(digits), value > 0 { return value }
        }

        // 5) số + "đ": "200000đ"
        if let groups = firstMatch(#"(\d+)\s*đ"#, in: lowered),
           let raw = groups[1],
           let value = Int64(raw), value > 0 {
            return value
        }

        return nil
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
