//
//  OneTouchResolver.swift
//  nano ewallet
//
//  "OneTouch" — nhận một nguồn bất kỳ (bộ nhớ tạm, ảnh trong thư viện) rồi tự nhận
//  diện là mã QR / tin nhắn chuyển khoản ngân hàng / số ví, trả về người nhận đã sẵn
//  sàng để điều hướng. Mirror `parseTextAndGo` + `processClipboardImage` trong
//  QrScanScreen.kt, tách riêng vì cả màn Quét QR lẫn lưới Dịch vụ ngoài Home đều gọi.
//

import Foundation
import UIKit
import CoreImage
import Vision

enum OneTouchResult {
    case bank(BankTransferDraft)
    case wallet(WalletTransferDraft)
    /// Không nhận diện được — kèm câu báo cho người dùng.
    case failure(String)
}

enum OneTouchResolver {

    /// Báo bước đang chạy để màn chờ đổi dòng chữ. Mỗi bước ở đây là một việc CÓ THẬT vừa
    /// bắt đầu, không phải chuỗi thông báo trang trí chạy theo đồng hồ.
    typealias ProgressHandler = @MainActor (String) -> Void

    /// Đọc bộ nhớ tạm: ưu tiên ảnh (người dùng hay chụp/lưu ảnh QR rồi copy), sau đó text.
    static func resolveClipboard(onProgress: ProgressHandler? = nil) async -> OneTouchResult {
        if let image = UIPasteboard.general.image {
            return await resolve(image: image, onProgress: onProgress)
        }
        let text = (UIPasteboard.general.string ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .failure("Bộ nhớ tạm trống. Hãy copy nội dung chuyển khoản hoặc ảnh mã QR trước.")
        }
        return await resolve(text: text, onProgress: onProgress)
    }

    /// Ảnh: thử tìm mã QR trước, không có thì OCR rồi xử như tin nhắn.
    static func resolve(image: UIImage, onProgress: ProgressHandler? = nil) async -> OneTouchResult {
        await report(onProgress, "Đang tìm mã QR trong ảnh...")
        if let raw = qrPayload(in: image) {
            await report(onProgress, "Đang đọc mã QR...")
            return await resolveQr(raw)
        }
        await report(onProgress, "Đang đọc chữ trong ảnh...")
        let text = await TextRecognizer.recognizeText(in: image)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .failure("Ảnh không có mã QR và không đọc được chữ")
        }
        return await resolve(text: text, onProgress: onProgress)
    }

    /// Nhận diện text là VÍ nội bộ hay NGÂN HÀNG.
    static func resolve(text: String, onProgress: ProgressHandler? = nil) async -> OneTouchResult {
        await report(onProgress, "Đang bóc tách nội dung...")
        return await resolveTextInner(text)
    }

    private static func report(_ handler: ProgressHandler?, _ message: String) async {
        guard let handler else { return }
        await MainActor.run { handler(message) }
    }

    private static func resolveTextInner(_ text: String) async -> OneTouchResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Số trơn -> thử verify là ví. Không phải ví thì báo rõ, KHÔNG thử bóc ngân hàng:
        // số trơn không kèm ngân hàng nên câu "không nhận ra ngân hàng" gây hiểu nhầm.
        if AmountParser.isBareNumber(trimmed) {
            if let name = try? await TransferService.verifyBeneficiary(
                VerifyBeneficiaryRequest(benUsername: trimmed)
            ) {
                return .wallet(walletDraft(username: trimmed, holderName: name, source: text))
            }
            return .failure("Không tìm thấy ví với số này (lưu ý không thể tự chuyển cho chính mình).")
        }

        // Tin nhắn -> để backend bóc ngân hàng + STK + số tiền.
        if let parsed = try? await BankService.parseMessage(rawMessage: trimmed) {
            return .bank(
                BankTransferDraft(
                    bin: parsed.bankBin, bankName: parsed.bankName ?? "Ngân hàng",
                    accNo: parsed.accountNumber, accType: 0, holderName: parsed.accountName,
                    prefillAmount: parsed.amount,
                    // OneTouch chỉ cần đúng SỐ TIỀN + TÀI KHOẢN. Bỏ nội dung backend bóc
                    // được để màn sau dùng nội dung mặc định (mirror forceDefaultMemo).
                    prefillContent: nil,
                    amountEditable: parsed.isAmountEditable, contentEditable: true
                )
            )
        }

        // Bóc ngân hàng trượt -> dò từng dãy số trong tin nhắn xem có phải số ví không.
        for candidate in AmountParser.numberCandidates(in: trimmed) {
            if let name = try? await TransferService.verifyBeneficiary(
                VerifyBeneficiaryRequest(benUsername: candidate)
            ) {
                return .wallet(walletDraft(username: candidate, holderName: name, source: text))
            }
        }
        return .failure("Không nhận diện được ngân hàng hoặc ví từ nội dung dán")
    }

    /// Mã QR (quét camera hoặc tìm thấy trong ảnh) -> nhờ backend verify CRC + tra chủ TK.
    static func resolveQr(_ rawValue: String) async -> OneTouchResult {
        do {
            let parsed = try await BankService.parseQr(rawQrData: rawValue)
            return .bank(
                BankTransferDraft(
                    bin: parsed.bankBin, bankName: parsed.bankName ?? "Ngân hàng",
                    accNo: parsed.accountNumber, accType: 0, holderName: parsed.accountName,
                    prefillAmount: parsed.amount, prefillContent: parsed.content,
                    amountEditable: parsed.isAmountEditable, contentEditable: parsed.isContentEditable
                )
            )
        } catch let error as APIError {
            return .failure(error.message)
        } catch {
            return .failure("Không đọc được mã QR, vui lòng thử lại")
        }
    }

    // MARK: - Private

    private static func walletDraft(
        username: String, holderName: String, source: String
    ) -> WalletTransferDraft {
        WalletTransferDraft(
            username: username, holderName: holderName,
            prefillAmount: AmountParser.parseVnd(from: source)
        )
    }

    /// Tìm mã QR trong ảnh. Thử Vision trước rồi mới tới `CIDetector`: `CIDetector` là API
    /// đời cũ, bỏ sót khá nhiều với mã bị mờ, chụp nghiêng hoặc đảo màu — đúng những kiểu ảnh
    /// người dùng hay chụp lại từ màn hình người khác.
    private static func qrPayload(in image: UIImage) -> String? {
        guard let cgImage = image.cgImage else { return nil }
        // Hướng ảnh nằm ở `UIImage.imageOrientation` chứ không nằm trong `cgImage`; bỏ qua
        // thì ảnh chụp từ camera (thường xoay 90°) không dò ra mã.
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        if let payload = visionQrPayload(cgImage: cgImage, orientation: orientation) {
            return payload
        }

        guard let detector = CIDetector(
            ofType: CIDetectorTypeQRCode, context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        ) else { return nil }
        let ciImage = CIImage(cgImage: cgImage).oriented(orientation)
        return (detector.features(in: ciImage) as? [CIQRCodeFeature])?.first?.messageString
    }

    private static func visionQrPayload(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) -> String? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        do {
            try VNImageRequestHandler(
                cgImage: cgImage, orientation: orientation, options: [:]
            ).perform([request])
        } catch {
            return nil
        }
        return (request.results as? [VNBarcodeObservation])?
            .compactMap(\.payloadStringValue)
            .first
    }
}
