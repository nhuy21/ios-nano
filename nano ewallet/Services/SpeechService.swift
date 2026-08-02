//
//  SpeechService.swift
//  nano ewallet
//
//  Mirror `EkycApi.parseTransferSpeech` — nhánh DỰ PHÒNG của luồng nhập số tiền bằng
//  giọng nói. Client tự bóc bằng regex trước (tức thì, không tốn mạng); chỉ khi regex
//  trượt trên một lượt TRÔNG NHƯ có đọc số thì mới nhờ AI ở backend phân tích lại.
//

import Foundation

struct ParseSpeechRequest: Encodable {
    let transcripts: [String]
}

/// `amount == 0` nghĩa là AI cũng không xác định được số tiền.
struct ParsedSpeech: Decodable {
    let amount: Int64
    let confidence: String?
}

enum SpeechService {
    /// `POST speech/parse-transfer`
    static func parseTransfer(transcripts: [String]) async throws -> ParsedSpeech {
        try await APIClient.shared.request(
            .post, "speech/parse-transfer",
            body: ParseSpeechRequest(transcripts: transcripts),
            auth: true, slow: true, as: ParsedSpeech.self
        )
    }
}
