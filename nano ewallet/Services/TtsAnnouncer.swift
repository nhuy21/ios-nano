//
//  TtsAnnouncer.swift
//  nano ewallet
//
//  Mirror TtsAnnouncer.kt — "Loa báo nhận tiền": đọc thành tiếng số tiền vừa nhận.
//  Android dùng TextToSpeech, iOS dùng AVSpeechSynthesizer.
//
//  GIỚI HẠN: chỉ đọc khi app đang MỞ. Push tới lúc app ở nền/đã đóng thì hệ thống tự
//  hiện thông báo khay và không chạy code app — bản Android cũng vậy
//  (onMessageReceived chỉ chạy ở foreground).
//

import Foundation
import AVFoundation

@MainActor
final class TtsAnnouncer {

    static let shared = TtsAnnouncer()
    private init() {}

    /// PHẢI giữ tham chiếu ở scope sống lâu — để synthesizer là biến cục bộ thì nó bị
    /// giải phóng giữa chừng và câu đọc tắt ngang.
    private let synthesizer = AVSpeechSynthesizer()

    /// Đọc "Đã nhận <số tiền> đồng".
    func announceReceived(amount: Int64) {
        guard amount > 0 else { return }
        speak("Đã nhận \(Self.readVndAmount(amount))")
    }

    /// Đọc câu xác nhận khi user vừa bật loa trong Cài đặt — để biết ngay là nó có kêu.
    func announceEnabled() {
        speak("Đã bật loa báo nhận tiền")
    }

    private func speak(_ text: String) {
        configureAudioSession()
        let utterance = AVSpeechUtterance(string: text)
        // Máy không cài giọng tiếng Việt thì để `nil` — hệ thống dùng giọng mặc định,
        // vẫn đọc được số (giống nhánh fallback setLanguage bên Android).
        utterance.voice = AVSpeechSynthesisVoice(language: "vi-VN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    /// `.playback` + `.duckOthers`: đọc đè lên nhạc/podcast đang phát (nhạc nhỏ lại rồi
    /// to trở lại), và vẫn kêu khi máy đang gạt nút im lặng — đây là thông báo tiền vào,
    /// bỏ lỡ thì mất ý nghĩa của tính năng.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true, options: [])
    }

    // MARK: - Đọc số tiền sang chữ tiếng Việt

    private static let units = ["", "một", "hai", "ba", "bốn", "năm", "sáu", "bảy", "tám", "chín"]
    private static let scales = ["", " nghìn", " triệu", " tỉ"]

    /// Vd 47500 -> "bốn mươi bảy nghìn năm trăm đồng".
    static func readVndAmount(_ amount: Int64) -> String {
        guard amount > 0 else { return "không đồng" }
        let words = readNumber(amount)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        return "\(words) đồng"
    }

    private static func readNumber(_ number: Int64) -> String {
        guard number != 0 else { return "không" }

        // Tách thành các nhóm 3 chữ số từ phải qua.
        var groups: [Int] = []
        var remaining = number
        while remaining > 0 {
            groups.append(Int(remaining % 1000))
            remaining /= 1000
        }

        var result = ""
        for index in stride(from: groups.count - 1, through: 0, by: -1) {
            let group = groups[index]
            guard group != 0 else { continue }
            // Nhóm cao nhất không đọc "không trăm"; nhóm sau đọc đầy đủ để giữ đúng vị trí
            // (vd 1_000_500 phải là "một triệu không trăm lẻ năm nghìn", không phải "năm").
            let isHighest = index == groups.count - 1
            result += readThreeDigits(group, full: !isHighest)
            if index < scales.count { result += scales[index] }
            result += " "
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func readThreeDigits(_ group: Int, full: Bool) -> String {
        let hundreds = group / 100
        let tens = (group % 100) / 10
        let ones = group % 10
        var result = ""

        if hundreds > 0 {
            result += "\(units[hundreds]) trăm"
        } else if full && (tens > 0 || ones > 0) {
            result += "không trăm"
        }

        if tens > 1 {
            result += " \(units[tens]) mươi"
            if ones == 1 { result += " mốt" }
            else if ones == 5 { result += " lăm" }
            else if ones > 0 { result += " \(units[ones])" }
        } else if tens == 1 {
            result += " mười"
            if ones == 5 { result += " lăm" }
            else if ones > 0 { result += " \(units[ones])" }
        } else if ones > 0 {
            if hundreds > 0 || full { result += " lẻ" }
            result += " \(units[ones])"
        }

        return result.trimmingCharacters(in: .whitespaces)
    }
}
