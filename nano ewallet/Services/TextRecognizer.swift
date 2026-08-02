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

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            // `accurate` vì tin nhắn CK có số tài khoản dài, nhận nhầm 1 chữ số là
            // chuyển sai người. Chậm hơn `fast` nhưng đây là thao tác một lần.
            request.recognitionLevel = .accurate
            // Vision chưa hỗ trợ vi-VN; en-US đọc tốt chữ Latin không dấu và chữ số,
            // vốn là phần cần thiết (số tài khoản, số tiền, tên ngân hàng).
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }
}
