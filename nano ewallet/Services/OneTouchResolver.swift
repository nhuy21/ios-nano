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
    /// Ảnh chứa NHIỀU người nhận thật — phải để người dùng tự chọn, không đoán hộ.
    ///
    /// Ảnh chụp nhóm chat chia tiền, ảnh có cả STK của chính mình, ảnh vừa có QR ngân hàng
    /// vừa có QR ví... đều là ca có thật. App tiền thì chọn nhầm tài khoản là mất tiền, mà
    /// lại sai lặng lẽ vì màn hình trông như đã bóc đúng.
    case choose(title: String, options: [OneTouchChoice])
    /// Không nhận diện được — kèm câu báo cho người dùng.
    case failure(String)
}

/// Hộp chọn đang mở, bọc thành `Identifiable` để dùng với `.fullScreenCover(item:)`.
///
/// Giữ tiêu đề CÙNG danh sách trong một giá trị thay vì hai biến rời: hai biến rời thì có
/// đường làm chúng lệch nhau (đổi danh sách mà quên đổi tiêu đề).
struct OneTouchChoiceList: Identifiable {
    let id = UUID()
    let title: String
    let options: [OneTouchChoice]
}

/// Một lựa chọn trong hộp chọn người nhận. Giữ nguyên kiểu draft của từng luồng thay vì ép
/// ví thành người nhận ngân hàng — hai luồng chuyển tiền khác nhau, gộp kiểu là nơi gọi phải
/// đoán ngược lại xem đây là ví hay ngân hàng.
enum OneTouchChoice: Identifiable {
    case bank(BankTransferDraft)
    case wallet(WalletTransferDraft)

    var id: String {
        switch self {
        case .bank(let draft): return "bank|\(draft.bin)|\(draft.accNo)"
        case .wallet(let draft): return "wallet|\(draft.username)"
        }
    }

    /// Tên chủ tài khoản — dòng chính trong hộp chọn.
    var holderName: String {
        switch self {
        case .bank(let draft): return draft.holderName
        case .wallet(let draft): return draft.holderName
        }
    }

    /// "Ngân hàng • số tài khoản" hoặc "Ví Nano • số ví" — dòng phụ.
    var subtitle: String {
        switch self {
        case .bank(let draft): return "\(draft.bankName) • \(draft.accNo)"
        case .wallet(let draft): return "Ví Nano • \(draft.username)"
        }
    }

    var systemImage: String {
        switch self {
        case .bank: return "building.columns"
        case .wallet: return "wallet.pass"
        }
    }
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
        let payloads = qrPayloads(in: image)

        if !payloads.isEmpty {
            await report(onProgress, "Đang đọc mã QR...")
            // Bóc SONG SONG từng mã: mỗi mã một lượt gọi API độc lập nên mã không phải QR
            // chuyển tiền (wifi, link, vé...) chỉ bị loại chứ không làm hỏng cả luồng.
            let drafts = await parseQrDrafts(payloads)

            if drafts.count == 1 {
                return .bank(drafts[0])
            }
            if drafts.count > 1 {
                return .choose(title: "Ảnh có nhiều mã QR", options: drafts.map(OneTouchChoice.bank))
            }
            // Có mã QR nhưng KHÔNG mã nào là mã chuyển tiền -> rơi xuống OCR thay vì dừng
            // hẳn: ảnh chụp tin nhắn CK kèm một mã QR không liên quan vẫn phải dùng được.
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
        //
        // GIỮ LẠI lỗi thay vì `try?`: backend phân biệt rõ "không bóc được nội dung" với
        // "tính năng chưa cấu hình / hết phiên / mất mạng", mà nuốt hết thành `nil` thì mọi
        // trường hợp đều hiện chung một câu chung chung, không lần ra được nguyên nhân.
        var parseError: String?
        do {
            let parsed = try await BankService.parseMessage(rawMessage: trimmed)

            // BE trả `accounts` khi văn bản có TỪ 2 TÀI KHOẢN THẬT trở lên (nó đã tra tên
            // từng cái, số nào không ra tên thì rụng). Lúc đó phải hỏi, không đoán.
            if let accounts = parsed.accounts, accounts.count > 1 {
                let options = accounts.map { account in
                    BankTransferDraft(
                        bin: account.bankBin,
                        bankName: account.bankName ?? "Ngân hàng",
                        accNo: account.accountNumber,
                        accType: 0,
                        holderName: account.accountName,
                        // Bỏ TRỐNG số tiền: BE chỉ trả MỘT số tiền cho cả đoạn văn bản, mà
                        // đoạn có nhiều tài khoản thường có nhiều số tiền — gán bừa là sai
                        // tiền một cách lặng lẽ. Trong app tiền thì không điền còn hơn điền sai.
                        prefillAmount: nil,
                        prefillContent: nil,
                        amountEditable: true,
                        contentEditable: true
                    )
                }
                return .choose(
                    title: "Ảnh có nhiều tài khoản",
                    options: options.map(OneTouchChoice.bank)
                )
            }

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
        } catch let error as APIError {
            parseError = error.message
        } catch {
            parseError = nil
        }

        // Bóc ngân hàng trượt -> dò từng dãy số trong tin nhắn xem có phải số ví không.
        //
        // Dò HẾT chứ không dừng ở số khớp đầu tiên: tin nhắn có thể chứa hai số ví thật
        // (ảnh chụp nhóm chat chia tiền), lấy đại một cái là chuyển nhầm người.
        //
        // Đổi lại phải chặn số lượt gọi: trước chỉ 1-2 lượt vì có `return` sớm, giờ là MỌI
        // dãy số trong ảnh (ngày tháng, số tiền, số điện thoại đều lọt vào). Chặn trên 8 và
        // gọi song song nên độ trễ vẫn xấp xỉ một lượt đi-về.
        let candidates = Array(AmountParser.numberCandidates(in: trimmed).prefix(8))
        let wallets = await withTaskGroup(of: WalletTransferDraft?.self) { group in
            for candidate in candidates {
                group.addTask {
                    guard let name = try? await TransferService.verifyBeneficiary(
                        VerifyBeneficiaryRequest(benUsername: candidate)
                    ) else { return nil }
                    return walletDraft(username: candidate, holderName: name, source: text)
                }
            }
            var found: [WalletTransferDraft] = []
            for await item in group {
                if let item { found.append(item) }
            }
            return found
        }

        if wallets.count == 1 {
            return .wallet(wallets[0])
        }
        if wallets.count > 1 {
            // Bỏ TRỐNG số tiền y như nhánh ngân hàng: `parseVnd` đọc số tiền từ CẢ đoạn văn
            // bản nên mọi lựa chọn sẽ nhận chung một con số, mà đoạn có nhiều người nhận
            // thường có nhiều số tiền khác nhau.
            let options = wallets.map { wallet in
                OneTouchChoice.wallet(
                    WalletTransferDraft(
                        username: wallet.username,
                        holderName: wallet.holderName,
                        payLinkToken: nil,
                        prefillAmount: nil
                    )
                )
            }
            return .choose(title: "Ảnh có nhiều số ví", options: options)
        }
        // Ưu tiên câu backend trả về — nó nói đúng chuyện gì đã xảy ra.
        return .failure(parseError ?? "Không nhận diện được ngân hàng hoặc ví từ nội dung dán")
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
    /// TẤT CẢ mã QR trong ảnh, đã loại trùng.
    ///
    /// Trả về mảng chứ không phải mã đầu tiên: cả Vision lẫn CIDetector đều KHÔNG cam kết
    /// thứ tự theo vị trí trên ảnh, nên "lấy mã đầu" thực chất là chọn ngẫu nhiên khi ảnh có
    /// nhiều mã. Gộp kết quả hai bộ dò vì chúng bỏ sót ở những ca khác nhau.
    private static func qrPayloads(in image: UIImage) -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        // Hướng ảnh nằm ở `UIImage.imageOrientation` chứ không nằm trong `cgImage`; bỏ qua
        // thì ảnh chụp từ camera (thường xoay 90°) không dò ra mã.
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        var found = visionQrPayloads(cgImage: cgImage, orientation: orientation)

        if let detector = CIDetector(
            ofType: CIDetectorTypeQRCode, context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        ) {
            let ciImage = CIImage(cgImage: cgImage).oriented(orientation)
            let extra = (detector.features(in: ciImage) as? [CIQRCodeFeature] ?? [])
                .compactMap(\.messageString)
            found.append(contentsOf: extra)
        }

        var seen = Set<String>()
        return found.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func visionQrPayloads(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        do {
            try VNImageRequestHandler(
                cgImage: cgImage, orientation: orientation, options: [:]
            ).perform([request])
        } catch {
            return []
        }
        return (request.results as? [VNBarcodeObservation] ?? [])
            .compactMap(\.payloadStringValue)
    }

    /// Bóc song song nhiều mã QR thành người nhận ngân hàng, bỏ mã không phải QR chuyển tiền
    /// và loại trùng theo (ngân hàng, số tài khoản).
    private static func parseQrDrafts(_ payloads: [String]) async -> [BankTransferDraft] {
        let parsed = await withTaskGroup(of: BankTransferDraft?.self) { group in
            for payload in payloads {
                group.addTask {
                    guard let info = try? await BankService.parseQr(rawQrData: payload) else {
                        return nil
                    }
                    return draft(from: info, amount: info.amount, keepContent: true)
                }
            }
            var all: [BankTransferDraft] = []
            for await item in group {
                if let item { all.append(item) }
            }
            return all
        }

        var seen = Set<String>()
        return parsed.filter { seen.insert("\($0.bin)|\($0.accNo)").inserted }
    }

    /// Dựng người nhận từ kết quả bóc của BE.
    /// - Parameters:
    ///   - amount: `nil` để bỏ trống ô số tiền — dùng khi văn bản có NHIỀU tài khoản, vì BE
    ///     chỉ trả MỘT số tiền cho cả đoạn text. Đoạn "cho a vay 20k / mb 097..." rồi
    ///     "chuyển a 25k / vcb 998..." mà gán số tiền của tài khoản kia là SAI TIỀN, lại sai
    ///     lặng lẽ vì trông như app đã bóc đúng. Gán tiền nào cho tài khoản nào cũng mơ hồ
    ///     y như chuyện chọn tài khoản, nên không đoán.
    ///   - keepContent: giữ nội dung nhúng trong mã QR; đường OCR thì bỏ để màn sau dùng
    ///     nội dung mặc định (mirror `forceDefaultMemo`).
    private static func draft(
        from info: ParsedQr, amount: Int?, keepContent: Bool
    ) -> BankTransferDraft {
        BankTransferDraft(
            bin: info.bankBin,
            bankName: info.bankName ?? "Ngân hàng",
            accNo: info.accountNumber,
            accType: 0,
            holderName: info.accountName,
            prefillAmount: amount,
            prefillContent: keepContent ? info.content : nil,
            amountEditable: amount == nil ? true : info.isAmountEditable,
            contentEditable: true
        )
    }
}
