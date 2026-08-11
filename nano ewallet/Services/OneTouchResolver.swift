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

    /// Ảnh: đọc mã QR và chữ trong CÙNG một lượt, rồi ghép lại.
    ///
    /// Đọc song song thay vì "có QR thì thôi đọc chữ": ảnh chụp mã QR TĨNH (không nhúng số
    /// tiền ở tag 54) luôn mất số tiền dù nó in rõ ngay cạnh mã. Hai việc độc lập nhau nên
    /// chạy cùng lúc cũng không chậm hơn đường cũ.
    static func resolve(image: UIImage, onProgress: ProgressHandler? = nil) async -> OneTouchResult {
        await report(onProgress, "Đang đọc nội dung ảnh...")

        // Đọc CẢ HAI, kể cả khi tìm thấy mã QR — khác đường cũ (thấy QR là bỏ hẳn phần chữ).
        // `recognizeText` đã tự chuyển sang luồng nền bên trong nên không chặn giao diện;
        // `qrPayloads` chạy đồng bộ nhưng nhanh hơn OCR nhiều nên đặt trước.
        let payloads = qrPayloads(in: image)
        let recognized = await TextRecognizer.recognizeWithHeader(in: image)
        let text = recognized.text.trimmingCharacters(in: .whitespacesAndNewlines)

        if !payloads.isEmpty {
            // Bóc SONG SONG từng mã: mỗi mã một lượt gọi API độc lập nên mã không phải QR
            // chuyển tiền (wifi, link, vé...) chỉ bị loại chứ không làm hỏng cả luồng.
            var drafts = await parseQrDrafts(payloads)

            // Chỉ điền số tiền từ chữ khi mã QR KHÔNG có sẵn, và luôn để người dùng sửa
            // được — số suy từ chữ là phỏng đoán, khác hẳn số nhúng trong QR động (số đó
            // chắc chắn nên vẫn khoá như cũ).
            //
            // Ảnh có NHIỀU tài khoản thì bỏ qua: gán số tiền nào cho tài khoản nào cũng là
            // đoán hộ, y như chuyện chọn tài khoản.
            if drafts.count == 1, drafts[0].prefillAmount == nil,
               let ocrAmount = AmountParser.ocrAmount(from: text) {
                drafts[0].prefillAmount = Int(ocrAmount)
                drafts[0].amountEditable = true
            }

            if drafts.count == 1 {
                return .bank(drafts[0])
            }
            if drafts.count > 1 {
                return .choose(title: "Ảnh có nhiều mã QR", options: drafts.map(OneTouchChoice.bank))
            }
            // Có mã QR nhưng KHÔNG mã nào là mã chuyển tiền -> rơi xuống đường đọc chữ thay
            // vì dừng hẳn: ảnh chụp tin nhắn CK kèm một mã QR không liên quan vẫn phải dùng
            // được.
        }

        guard !text.isEmpty else {
            return .failure("Ảnh không có mã QR và không đọc được chữ")
        }
        return await resolve(text: text, header: recognized.header, onProgress: onProgress)
    }

    /// Nhận diện text là VÍ nội bộ hay NGÂN HÀNG.
    /// - Parameter header: chữ ở VÙNG TIÊU ĐỀ ảnh (tên cuộc trò chuyện). Chỉ có khi nguồn là
    ///   ảnh; dán chữ trực tiếp thì rỗng, và nhánh suy người nhận từ danh bạ sẽ bỏ qua.
    static func resolve(
        text: String, header: String = "", onProgress: ProgressHandler? = nil
    ) async -> OneTouchResult {
        await report(onProgress, "Đang bóc tách nội dung...")
        return await resolveTextInner(text, header: header)
    }

    private static func report(_ handler: ProgressHandler?, _ message: String) async {
        guard let handler else { return }
        await MainActor.run { handler(message) }
    }

    private static func resolveTextInner(_ text: String, header: String) async -> OneTouchResult {
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

        // Không có SỐ nào trong tin nhắn -> thử suy người nhận từ TÊN CUỘC TRÒ CHUYỆN.
        //
        // Ca thật: đã lưu "Linh", Linh nhắn "chuyển tao 20k" — tin nhắn không có số nào cả.
        // Trước đây đây là đường cụt: báo lỗi và MẤT luôn những gì đã bóc được (số tiền).
        //
        // Chỉ dùng chữ ở VÙNG TIÊU ĐỀ, không dùng chữ cả ảnh — xem `recognizeWithHeader`.
        if let result = await matchFromContacts(header: header, amount: AmountParser.parseVnd(from: text)) {
            return result
        }

        // Ưu tiên câu backend trả về — nó nói đúng chuyện gì đã xảy ra.
        return .failure(parseError ?? "Không nhận diện được ngân hàng hoặc ví từ nội dung dán")
    }

    /// Suy người nhận từ tên cuộc trò chuyện, đối chiếu danh bạ.
    ///
    /// `nil` khi không có tiêu đề, danh bạ rỗng, hoặc không khớp ai — nơi gọi giữ nguyên lỗi
    /// gốc thay vì đổi thành câu khác gây hiểu nhầm.
    /// `@MainActor` vì cả `BeneficiaryStore` lẫn `BankCache` đều bị cô lập ở main actor.
    /// Toàn bộ hàm chỉ đọc dữ liệu đã có sẵn trong bộ nhớ nên không chặn giao diện.
    @MainActor
    private static func matchFromContacts(header: String, amount: Int64?) async -> OneTouchResult? {
        let header = header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !header.isEmpty else { return nil }

        let contacts = await BeneficiaryStore.shared.get()
        guard !contacts.isEmpty else { return nil }

        // Bỏ contact thiếu dữ liệu để chuyển: ví cần username, ngân hàng cần cả BIN lẫn số TK.
        let usable = contacts.filter { contact in
            switch contact.type {
            case .wallet: return !(contact.benUsername ?? "").isEmpty
            case .bankAccount:
                return !(contact.bankNo ?? "").isEmpty && !(contact.accNo ?? "").isEmpty
            }
        }
        let matches = RecipientMatcher.top(RecipientMatcher.match([header], in: usable))
        guard !matches.isEmpty else { return nil }

        let choices = matches.compactMap { choice(for: $0.contact, amount: amount) }
        guard !choices.isEmpty else { return nil }
        if choices.count == 1 { return single(choices[0]) }
        // Nhiều người cùng khớp (hai người cùng đặt tên gợi nhớ "Linh") -> phải hỏi.
        return .choose(title: "Có \(choices.count) người trùng tên", options: choices)
    }

    /// `@MainActor` vì `BankCache` (tra tên ngân hàng theo BIN) bị cô lập ở main actor.
    @MainActor
    private static func choice(for contact: Beneficiary, amount: Int64?) -> OneTouchChoice? {
        switch contact.type {
        case .wallet:
            guard let username = contact.benUsername, !username.isEmpty else { return nil }
            return .wallet(WalletTransferDraft(
                username: username,
                holderName: contact.displayName,
                payLinkToken: nil,
                prefillAmount: amount
            ))
        case .bankAccount:
            guard let bin = contact.bankNo, !bin.isEmpty,
                  let accNo = contact.accNo, !accNo.isEmpty else { return nil }
            return .bank(BankTransferDraft(
                bin: bin,
                bankName: BankCache.shared.bank(bin: bin)?.shortName ?? "Ngân hàng",
                accNo: accNo,
                accType: 0,
                holderName: contact.accName ?? contact.displayName,
                prefillAmount: amount.map(Int.init),
                prefillContent: nil,
                // Số tiền suy từ chữ là phỏng đoán -> luôn cho sửa.
                amountEditable: true,
                contentEditable: true
            ))
        }
    }

    private static func single(_ choice: OneTouchChoice) -> OneTouchResult {
        switch choice {
        case .bank(let draft): return .bank(draft)
        case .wallet(let draft): return .wallet(draft)
        }
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

// MARK: - Khớp người nhận từ danh bạ

/// Một người trong danh bạ khớp được với mẩu chữ.
struct ContactMatch {
    let contact: Beneficiary
    /// Khớp vào TÊN GỢI NHỚ (không phải tên chủ tài khoản).
    let viaNickname: Bool
    /// Số TỪ của tên khớp được — tên khớp trọn vẹn hơn thì đáng tin hơn.
    let tokens: Int
    /// Tổng ký tự khớp, dùng phân định khi bằng số từ.
    let chars: Int
}

/// Khớp người nhận trong danh bạ từ một mẩu chữ (tên cuộc trò chuyện đọc được ở đầu ảnh chụp
/// màn hình) — mirror `matchRecipients`/`topContactMatches` bên Android.
///
/// Chỉ dùng khi tin nhắn KHÔNG có số tài khoản nào: số tài khoản là thứ ĐỌC được nên luôn
/// thắng cái tên SUY ra.
enum RecipientMatcher {

    /// Khớp theo TỪ, xét cả tên gợi nhớ lẫn từng từ của tên chủ tài khoản.
    ///
    /// Khớp theo TỪ chứ không phải chuỗi con, nên không nhầm "mẹ" (me) với "mến" (men).
    /// Không phân biệt loại danh bạ: ví và ngân hàng đều xét, vì tên một tài khoản ngân hàng
    /// đã lưu (vd "chủ nhà") cũng là cái người dùng nhận ra.
    static func match(_ candidates: [String], in contacts: [Beneficiary]) -> [ContactMatch] {
        let said = Set(candidates.flatMap(words))
        guard !said.isEmpty else { return [] }

        var out: [ContactMatch] = []
        for contact in contacts {
            // Tính RIÊNG hai nguồn tên để biết khớp vào đâu — gộp chung thì mất thông tin đó
            // và không thể cho tên gợi nhớ thắng tên chủ tài khoản.
            let nick = words(contact.nickname ?? "")
            if !nick.isEmpty, nick.allSatisfy(said.contains) {
                out.append(ContactMatch(
                    contact: contact, viaNickname: true,
                    tokens: nick.count, chars: nick.reduce(0) { $0 + $1.count }
                ))
                continue
            }

            let acc = words(contact.accName ?? "")
            // Đòi từ CUỐI (tên riêng) phải có mặt: khớp mỗi họ/đệm ("nguyen", "van") thì gần
            // như cả danh bạ đều trúng.
            if let last = acc.last, said.contains(last) {
                let hit = acc.filter(said.contains)
                out.append(ContactMatch(
                    contact: contact, viaNickname: false,
                    tokens: hit.count, chars: hit.reduce(0) { $0 + $1.count }
                ))
            }
        }
        return out
    }

    /// Lọc còn nhóm ưu tiên CAO NHẤT rồi giữ các contact ĐỒNG ĐIỂM ở nhóm đó.
    ///
    /// Còn nhiều hơn một tức là thật sự không phân định được (vd hai người cùng đặt tên gợi
    /// nhớ "Linh") — lúc đó nơi gọi phải HỎI chứ không được chọn hộ.
    ///
    /// TÊN GỢI NHỚ THẮNG TÊN CHỦ TÀI KHOẢN, rồi mới xét độ dài từ khớp. Vì tên gợi nhớ là do
    /// NGƯỜI DÙNG TỰ ĐẶT cho người này, còn tên chủ tài khoản là do ngân hàng trả về.
    ///
    /// Ca hỏng nếu không có thứ bậc này: "NGUYỄN THÙY LINH" lưu là "Yến", và "Nguyễn Thị Yến"
    /// lưu là "Linh". Nhắc "Yến" thì cả hai cùng khớp với ĐIỂM BẰNG NHAU (3 ký tự) -> chọn
    /// theo thứ tự API trả về, tức tuỳ may.
    static func top(_ matches: [ContactMatch]) -> [ContactMatch] {
        guard !matches.isEmpty else { return [] }
        let tier = matches.contains(where: \.viaNickname)
            ? matches.filter(\.viaNickname)
            : matches
        guard let bestTokens = tier.map(\.tokens).max() else { return [] }
        let sameTokens = tier.filter { $0.tokens == bestTokens }
        guard let bestChars = sameTokens.map(\.chars).max() else { return [] }
        return sameTokens.filter { $0.chars == bestChars }
    }

    /// Tách chuỗi thành các TỪ đã bỏ dấu + viết thường, bỏ từ quá ngắn (<2) để tránh nhiễu.
    private static func words(_ s: String) -> [String] {
        normalizeName(s)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { $0.count >= 2 }
    }

    /// Bỏ dấu tiếng Việt + viết thường. `đ`/`Đ` phải thay tay vì không tách ra được như các
    /// dấu khác.
    private static func normalizeName(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
