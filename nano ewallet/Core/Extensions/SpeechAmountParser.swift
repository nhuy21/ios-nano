//
//  SpeechAmountParser.swift
//  nano ewallet
//
//  Mirror phần bóc số tiền trong VoiceInput.kt — đọc số tiền từ câu NÓI, khác
//  `AmountParser` (đọc từ text gõ/dán) ở chỗ phải hiểu số viết bằng CHỮ tiếng Việt
//  ("hai trăm lẻ một nghìn") và các biến thể recognizer hay trả về.
//

import Foundation

enum SpeechAmountParser {

    /// Trần an toàn — recognizer nghe nhầm có thể ra số khổng lồ.
    private static let maxAmount: Int64 = 999_999_999

    /// Chọn số tiền từ nhiều phương án nhận diện: ưu tiên nhóm >= 1.000 (số nhỏ thường
    /// là nghe nhầm), rồi lấy giá trị xuất hiện NHIỀU nhất.
    static func pickAmount(from candidates: [String]) -> Int64? {
        let parsed = candidates.compactMap { parse($0) }
        guard !parsed.isEmpty else { return nil }

        let pool = parsed.filter { $0 >= 1_000 }.isEmpty ? parsed : parsed.filter { $0 >= 1_000 }
        var counts: [Int64: Int] = [:]
        for value in pool { counts[value, default: 0] += 1 }
        guard let top = counts.values.max() else { return nil }
        return pool.first { counts[$0] == top }
    }

    static func parse(_ raw: String) -> Int64? {
        var text = raw.lowercased()

        // Dấu . , giữa chữ số là PHÂN CÁCH HÀNG NGHÌN khi theo sau đúng 3 chữ số
        // ("201.098", "1.500.000") -> bỏ để dính liền. Ngược lại ("1,5 triệu") là dấu
        // THẬP PHÂN nên giữ lại cho nhánh số+đơn vị xử lý.
        text = replacing(#"(?<=\d)[.,](?=\d{3}(?!\d))"#, in: text, with: "")

        // 1) Số + đơn vị, cộng dồn mọi cụm ("1 triệu 200 nghìn"), hỗ trợ thập phân.
        let unitMatches = matches(#"(\d+)(?:[.,](\d{1,2}))?\s*(nghìn|ngàn|triệu|tr|tỷ|tỉ|k)"#, in: text)
        if !unitMatches.isEmpty {
            var sum: Int64 = 0
            for match in unitMatches {
                let multiplier = unitMultiplier(match.groups[3] ?? "")
                sum += (match.groups[1].flatMap { Int64($0) } ?? 0) * multiplier
                // "1,5 triệu" -> + 5 * 1.000.000/10
                if let frac = match.groups[2], !frac.isEmpty, let fracValue = Int64(frac) {
                    var divisor: Int64 = 1
                    for _ in 0..<frac.count { divisor *= 10 }
                    sum += fracValue * (multiplier / divisor)
                }
            }
            // Nhóm số LẺ dính ngay sau đơn vị cuối — recognizer hay tách kiểu
            // "201 nghìn 098" -> 201.098. Chỉ nhận nhóm <= 3 chữ số đứng sát sau.
            if let last = unitMatches.last {
                let tail = String(text[last.range.upperBound...])
                if let m = matches(#"^\s*(\d{1,3})(?!\d)"#, in: tail).first,
                   let extra = m.groups[1].flatMap({ Int64($0) }) {
                    sum += extra
                }
            }
            return sum > 0 ? min(max(sum, 1), maxAmount) : nil
        }

        // 2) Số thuần (không chữ cái nào): "500000", "201098"
        if !text.contains(where: { $0.isLetter }) {
            let digits = String(text.filter(\.isNumber).prefix(12))
            if let value = Int64(digits), value > 0 { return min(value, maxAmount) }
        }

        // 3) Số bằng CHỮ, có thể trộn token số.
        return parseVietnameseWords(text).map { min(max($0, 1), maxAmount) }
    }

    /// Câu nói "trông như" có đọc số tiền không — có chữ số, hoặc có từ chỉ số/đơn vị
    /// tiếng Việt. Dùng để quyết định có nhờ AI backend bóc lại hay không: lượt nói
    /// linh tinh thì đừng tốn một vòng mạng.
    static func containsAmountHint(_ raw: String) -> Bool {
        let lowered = raw.lowercased()
        if lowered.contains(where: \.isNumber) { return true }
        let tokens = lowered.split(whereSeparator: { !$0.isLetter }).map(String.init)
        return tokens.contains { numberWords.contains($0) || $0 == "k" || $0 == "tr" }
    }

    private static let numberWords: Set<String> = [
        "không", "một", "mốt", "hai", "ba", "bốn", "tư", "năm", "lăm", "nhăm",
        "sáu", "bảy", "bẩy", "tám", "chín", "mười", "mươi", "trăm",
        "nghìn", "ngàn", "triệu", "tỷ", "tỉ", "rưỡi", "lẻ", "linh", "đồng",
    ]

    private static func unitMultiplier(_ unit: String) -> Int64 {
        switch unit {
        case "k", "nghìn", "ngàn": return 1_000
        case "tr", "triệu": return 1_000_000
        case "tỷ", "tỉ": return 1_000_000_000
        default: return 1
        }
    }

    private static let digitWords: [String: Int64] = [
        "không": 0, "một": 1, "mốt": 1, "hai": 2, "ba": 3,
        "bốn": 4, "tư": 4, "năm": 5, "lăm": 5, "nhăm": 5,
        "sáu": 6, "bảy": 7, "bẩy": 7, "tám": 8, "chín": 9,
    ]

    /// Số viết bằng chữ tiếng Việt. Giữ cả token SỐ vì recognizer hay trộn
    /// ("hai trăm lẻ một nghìn 098").
    private static func parseVietnameseWords(_ text: String) -> Int64? {
        let tokens = text
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }

        var result: Int64 = 0    // tổng đã chốt qua các bậc nghìn/triệu/tỷ
        var current: Int64 = 0   // giá trị nhóm hiện tại
        var lastUnit: Int64 = 0  // chữ số vừa gặp — để "mươi" nhân 10
        var lastScale: Int64 = 0 // bậc gần nhất — để "rưỡi" cộng nửa bậc
        var sawZero = false      // vừa gặp "không" — để "không trăm" = 0, không phải 100
        var found = false

        for token in tokens {
            switch token {
            case "lẻ", "linh":
                lastUnit = 0
            case "mười":
                current += 10; lastUnit = 0; found = true
            case "mươi":
                current += lastUnit * 9; lastUnit = 0 // u đã cộng 1 lần -> thành u*10
            case "trăm":
                current = (current == 0 && !sawZero ? 1 : current) * 100
                lastUnit = 0; sawZero = false; found = true
            case "nghìn", "ngàn":
                result += (current == 0 ? 1 : current) * 1_000
                current = 0; lastUnit = 0; sawZero = false; lastScale = 1_000; found = true
            case "triệu":
                result += (current == 0 ? 1 : current) * 1_000_000
                current = 0; lastUnit = 0; sawZero = false; lastScale = 1_000_000; found = true
            case "tỷ", "tỉ":
                result += (current == 0 ? 1 : current) * 1_000_000_000
                current = 0; lastUnit = 0; sawZero = false; lastScale = 1_000_000_000; found = true
            case "rưỡi":
                if lastScale > 0 { result += lastScale / 2 }
            default:
                if let digit = digitWords[token] {
                    current += digit; lastUnit = digit; found = true
                    if token == "không" { sawZero = true }
                } else if token.allSatisfy(\.isNumber),
                          let value = Int64(String(token.prefix(12))) {
                    current += value; lastUnit = 0; found = true
                }
                // các từ khác ("chuyển", "cho", "đồng"...) bỏ qua
            }
        }

        let total = result + current
        return (found && total > 0) ? total : nil
    }

    // MARK: - Regex helper

    struct Match {
        let range: Range<String.Index>
        let groups: [String?]
    }

    private static func matches(_ pattern: String, in text: String) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let full = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: full).compactMap { result in
            guard let range = Range(result.range, in: text) else { return nil }
            let groups = (0..<result.numberOfRanges).map { index -> String? in
                Range(result.range(at: index), in: text).map { String(text[$0]) }
            }
            return Match(range: range, groups: groups)
        }
    }

    private static func replacing(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template
        )
    }
}
