# Chuyển tiền nhanh qua Siri (App Intents)

Trạng thái: **đã code (mục 6 xong), chưa build/test trên máy thật** — máy viết code này
không có Xcode. Việc còn lại thuần là build + test, xem "Đã code" cuối file.

## 1. Mục tiêu

Người dùng nói *"Hey Siri, chuyển 5 nghìn cho A trên Nano Wallet"* → tiền được chuyển,
mức độ "chạy ngầm" hay "phải mở app" phụ thuộc số tiền — chia **3 tầng theo đúng 2 ngưỡng
đã có sẵn trong app** (`limitPin`/`limitFace`, xem mục 7), không tự nghĩ ngưỡng mới:

| Số tiền | Hành vi |
|---|---|
| `amount ≤ limitPin` | Siri đọc lại 1 lần để xác nhận → Face ID (overlay hệ thống) → ký & chuyển **hoàn toàn chạy ngầm**, không mở app. |
| `limitPin < amount ≤ limitFace` | **Mở app**, vào thẳng màn xác nhận đã điền sẵn người nhận/số tiền (tái dùng `Route.walletTransferAmount`) — người dùng tự xem lại rồi xác nhận như luồng thường. |
| `amount > limitFace` | **Không chuyển được bằng cách nào** — báo lỗi "vượt hạn mức", dừng ngay, không mở app. |

Lý do chia 3 tầng thay vì làm 1 kiểu duy nhất: khảo sát cho thấy MoMo (đối thủ cùng thị
trường, đã có Siri tiếng Việt) chọn cách an toàn — **luôn** đưa người dùng vào màn hình
app để xem lại/sửa/xác nhận trước khi tiền đi, không tự động hoàn toàn dù ở mức nào. Lý do
là rủi ro Siri nghe sai số tiền/tên người. Ở đây mình lấy `limitPin` làm ranh giới "đủ nhỏ
để chấp nhận rủi ro nghe sai" — cùng logic với việc `limitPin` vốn đã là ngưỡng "được dùng
xác thực nhẹ hơn" trong app, không phải số tự chọn.

Căn cứ khả thi: Siri (App Intents, không phải "Siri AI" mới của Apple) đã hỗ trợ tiếng
Việt từ iOS 18.4, và MoMo — ứng dụng ví cùng thị trường — đã triển khai đúng kiểu lệnh
"chuyển tiền bằng giọng nói" này rồi.

### Phiên bản iOS: deployment target 16.0, shortcut Siri gate ở 18.4

**CẬP NHẬT (sau khi hạ deployment target):** doc này viết khi target là iOS 26. Target hiện
tại của app là **16.0** (đồng bộ với các app khác của công ty). Ảnh hưởng tới tính năng này:

- `AppIntents`, `AppEntity`, `AppShortcutsProvider` — đều là iOS 16, đúng bằng target nên
  dùng trực tiếp, KHÔNG cần `@available`.
- **`QuickTransferShortcuts` bọc `@available(iOS 18.4, *)`** — đó là mốc Apple thêm tiếng Việt
  cho Siri. `phrases` là tiếng Việt nên máy 16-18.3 không bao giờ khớp được; để shortcut hiện
  trong app Shortcuts ở những bản đó chỉ gây rối (thấy mục nhưng ra lệnh thì Siri không hiểu).
- `QuickTransferIntent`/`QuickTransferOpenAppIntent` **không** bọc — vẫn iOS 16+, còn dùng qua
  `opensIntent` ở tầng 2 và người dùng tự tạo shortcut trong app Shortcuts được.
- `LAContext`/Secure Enclave cho Face ID ngoài UI app — có từ iOS 11, không ảnh hưởng.

**Không nhắm iOS 27** ở giai đoạn này: "App Schemas" (Siri AI dựng trên Gemini, hiểu app
sâu hơn không cần khai `phrases` thủ công) là tính năng riêng của iOS 27, nhưng bản đó mới
~3% máy dùng và còn beta. Ghi chú để sau: nếu Apple bổ sung domain Payments/Finance vào App
Schemas, có thể gate thêm 1 lớp `@available(iOS 27, *)` để adopt riêng, KHÔNG nâng
deployment target chung của app chỉ vì lớp đó — hiện App Schemas mới có domain
Calendar/Messages/Reminders/System, chưa có gì cho tài chính nên chưa có gì để adopt.

## 2. Vì sao không cần Widget Extension riêng

Khác với ý tưởng Widget đã bàn trước đó (cần thêm 1 target Extension + App Group để chia
sẻ Keychain), **App Intents gọi từ Siri/Shortcuts chạy thẳng trong tiến trình app chính**
— hệ thống launch app ở chế độ nền (không hiện UI) để chạy `perform()`. Vì cùng tiến
trình/container với app, intent đọc được Keychain (token đăng nhập, khoá sinh trắc) và
gọi service hiện có (`BeneficiaryStore`, `BiometricService`, `TransferService`) như code
bình thường trong app — **không cần target mới, không cần App Group.**

Nếu sau này làm thêm Widget (bấm 1 nút cố định trên Home Screen), lúc đó mới cần Widget
Extension riêng + chia sẻ Keychain access group — nhưng có thể **dùng lại đúng
`AppIntent`** thiết kế ở đây, không phải viết lại logic.

## 3. Ánh xạ danh bạ hiện có → entity cho Siri

`Beneficiary` ([`Models/BeneficiaryModels.swift`](../nano%20ewallet/Models/BeneficiaryModels.swift))
đã có **2 tên khác nhau** cho 1 người, phải xử lý cả hai khi tìm theo giọng nói:

- `nickname` — tên người dùng tự đặt (ví dụ "Mẹ"), ưu tiên hiển thị cao nhất.
- `accName` — tên thật chủ tài khoản/ví do BE trả về (ví dụ "NGUYEN VAN A"), có với cả 2
  loại `bankAccount`/`wallet`.
- `benUsername` — số ví, chỉ có với loại `wallet`.
- `displayName` (computed) = `nickname ?? accName ?? benUsername` — **không dùng trực
  tiếp cho việc tìm kiếm bằng giọng nói**, vì người dùng có thể nói tên thật ("Nguyễn Văn
  A") dù danh bạ đang hiển thị nickname ("Mẹ"), hoặc ngược lại.

```swift
struct WalletContactEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Người nhận" }
    static var defaultQuery = WalletContactQuery()

    let id: String              // Beneficiary.id
    let name: String            // nickname ?? accName ?? benUsername (dùng để hiển thị)
    let subtitle: String        // accName thật (nếu name đang là nickname) hoặc số ví/số TK

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(subtitle)")
    }
}

struct WalletContactQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [WalletContactEntity] {
        let all = await BeneficiaryStore.shared.get()
        return all
            .filter {
                ($0.nickname?.localizedCaseInsensitiveContains(string) ?? false)
                    || ($0.accName?.localizedCaseInsensitiveContains(string) ?? false)
            }
            .map { b in
                WalletContactEntity(
                    id: b.id,
                    name: b.displayName,
                    subtitle: b.nickname != nil ? (b.accName ?? b.benUsername ?? "") : (b.benUsername ?? "")
                )
            }
    }

    func entities(for identifiers: [String]) async throws -> [WalletContactEntity] {
        let all = await BeneficiaryStore.shared.get()
        return all.filter { identifiers.contains($0.id) }.map { /* map như trên */ }
    }
}
```

**Điểm mấu chốt cho việc phân biệt trùng tên:** `subtitle` PHẢI là thứ khác với `name`,
không thôi Siri đọc lại disambiguation ("bạn muốn nói ai") mà 2 lựa chọn nghe giống nhau
y hệt. Vì `name` đã ưu tiên nickname, nên `subtitle` ưu tiên ngược lại — tên thật/số ví —
để luôn có 2 thông tin khác nhau đọc lên.

## 4. Intent chuyển tiền — 2 intent, không phải 1

`AppIntent.openAppWhenRun` là **static property**, cố định theo KIỂU intent, không thể
đổi theo giá trị `amount` lúc chạy (xem thread trên Apple Developer Forums — đây là câu
hỏi nhiều người gặp, câu trả lời chính thức là không có cách set động). Nên bắt buộc phải
tách **2 intent**: 1 chạy ngầm, 1 mở app — intent chạy ngầm tự quyết định gọi qua intent
mở app khi cần, qua `.result(opensIntent:)`.

```swift
/// Intent chính, expose ra Siri qua AppShortcutsProvider — LUÔN chạy ngầm
/// (openAppWhenRun mặc định false). Tự quyết định có handoff sang intent mở app hay không.
struct QuickTransferIntent: AppIntent {
    static var title: LocalizedStringResource = "Chuyển tiền"
    static var description = IntentDescription("Chuyển tiền cho một người trong danh bạ ví.")

    @Parameter(title: "Người nhận") var recipient: WalletContactEntity
    @Parameter(title: "Số tiền") var amount: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Chuyển \(\.$amount) cho \(\.$recipient)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let limitPin = WalletStore.shared.limitPin ?? WalletStore.defaultLimitPin // kéo theo từng user, từ DB
        let limitFace = TransferLimits.faceFixed // 10.000.000đ, CỐ ĐỊNH — không theo user, không gọi API

        // Tầng 3: vượt limitFace — không chuyển được bằng cách nào, dừng ngay.
        guard Int64(amount) <= limitFace else {
            throw QuickTransferError.overLimit
        }

        // Tầng 2: giữa limitPin và limitFace — handoff sang intent MỞ APP, không tự làm gì thêm.
        guard Int64(amount) <= limitPin else {
            return .result(opensIntent: QuickTransferOpenAppIntent(recipient: recipient, amount: amount))
        }

        // Tầng 1: dưới limitPin — Siri đọc lại xác nhận 1 lần, rồi chạy ngầm hoàn toàn.
        try await requestConfirmation(
            actionName: .transfer,
            dialog: "Xác nhận chuyển \(amount)đ cho \(recipient.name)?"
        )

        // 1. Xin Face ID qua LAContext — overlay hệ thống, không mở UI app.
        // 2. Ký payload bằng BiometricKeyStore (cùng logic BiometricService.verifyTransfer).
        // 3. Gọi TransferService/API chuyển tiền tới recipient.
        return .result(dialog: "Đã chuyển \(amount)đ cho \(recipient.name)")
    }
}

/// Intent phụ — KHÔNG expose phrase riêng, chỉ được `QuickTransferIntent` gọi tới qua
/// `opensIntent`. `openAppWhenRun = true` ép hệ thống mở app trước khi perform() chạy.
struct QuickTransferOpenAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Xác nhận chuyển tiền trong app"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Người nhận") var recipient: WalletContactEntity
    @Parameter(title: "Số tiền") var amount: Int

    @MainActor
    func perform() async throws -> some IntentResult {
        // Cùng pattern pendingWalletTransferShortcut đã có ở DeepLinkStore (mục 2 tham
        // chiếu) — đặt cờ, để MainTabView tự tiêu thụ 1 lần và đẩy vào
        // Route.walletTransferAmount, KHÔNG tự điều hướng trực tiếp từ đây.
        DeepLinkStore.shared.requestQuickTransfer(
            draft: WalletTransferDraft(
                username: recipient.id, holderName: recipient.name, prefillAmount: Int64(amount)
            )
        )
        return .result()
    }
}

struct QuickTransferShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickTransferIntent(),
            phrases: [
                "Chuyển \(.applicationName) cho \(\.$recipient)",
                "Chuyển tiền cho \(\.$recipient) trên \(.applicationName)",
            ],
            shortTitle: "Chuyển tiền nhanh",
            systemImageName: "paperplane.fill"
        )
    }
}
```

Chỉ `QuickTransferIntent` có `phrases` — `QuickTransferOpenAppIntent` không cần (và không
nên) xuất hiện trong danh sách Shortcuts riêng, vai trò của nó chỉ là điểm hạ cánh khi
tầng 2 cần mở app, người dùng không tự gọi trực tiếp.

## 5. Bảo mật — không tạo đường tắt bỏ Face ID

Áp dụng riêng cho **tầng 1** (chạy ngầm, `amount ≤ limitPin`) — tầng 2 đi qua màn hình app
bình thường, dùng đúng cơ chế xác thực sẵn có ở đó (Face ID hoặc PIN theo lựa chọn người
dùng), không cần quy tắc riêng.

Tầng 1 tái dùng đúng payload ký hiện có ở
[`BiometricService.verifyTransfer`](../nano%20ewallet/Services/BiometricService.swift):
`"<transactionId>|<amount>|<recipient>|<deviceId>"`, ký bằng khoá Secure Enclave qua
`BiometricKeyStore`. Face ID ở tầng này **bắt buộc, không có nhánh fallback về PIN** — vì
Siri không gõ được PIN, và nói đúng câu lệnh không đồng nghĩa đã xác thực là chủ ví.

Điều kiện: máy phải đã **bật xác thực giao dịch bằng sinh trắc** trước (cờ có trong
`BiometricService.transferStatus()`) — nếu chưa bật, `QuickTransferIntent` phải báo lỗi rõ
("Bật xác thực Face ID trong Cài đặt trước") ngay từ đầu, kể cả khi `amount ≤ limitPin`,
thay vì rơi về xin mật khẩu 6 số.

## 6. Việc cần làm

1. `WalletContactEntity` + `WalletContactQuery` (mục 3) — file mới, ví dụ
   `Services/Intents/WalletContactEntity.swift`.
2. `QuickTransferIntent` + `QuickTransferOpenAppIntent` + `QuickTransferShortcuts` + enum lỗi
   `QuickTransferError` (mục 4) — file mới, ví dụ `Services/Intents/QuickTransferIntent.swift`.
3. `DeepLinkStore.requestQuickTransfer(draft:)` / `consumeQuickTransfer()` — thêm đúng
   khuôn `pendingWalletTransferShortcut` đã có (xem mục 2), và 1 nhánh `.onChange` mới
   trong `MainTabView` gọi `openOnHome(.walletTransferAmount(draft))`.
4. Thêm framework `AppIntents` vào target chính (không cần target mới).
5. Nhánh lỗi: chưa bật sinh trắc, số dư không đủ, người nhận không tồn tại/đã xoá khỏi
   danh bạ giữa lúc nói và lúc chạy — mỗi nhánh trả `IntentDialog` báo rõ, không im lặng
   thất bại.

## 7. Giới hạn & rủi ro đã biết

- Siri tiếng Việt (cổ điển) còn "bỡ ngỡ" với câu phức tạp theo báo chí — phải tự test
  nhiều cách nói số tiền ("5 nghìn" / "5k" / "năm nghìn") trên máy thật, không đoán bằng
  code.
- Trùng tên trong danh bạ: xử lý được qua disambiguation tự động của hệ thống (mục 3),
  nhưng vẫn cần `subtitle` đủ khác biệt mới có tác dụng.
- **`limitFace` = 10.000.000đ, hằng số CỨNG, giống nhau cho mọi user** — khác `limitPin`
  (kéo theo từng user từ DB qua `WalletStore.shared.limitPin`). Trên ngưỡng này thì không
  chuyển được bằng cách nào trong app cả (BE/Bảo Kim từ chối thẳng, mã lỗi 128, xem ghi chú
  ở [`WithdrawView.swift:33`](../nano%20ewallet/UI/Screens/transfer/WithdrawView.swift)).
  Tầng 3 ở mục 1 chặn đúng từ phía client trước khi gọi API, nhưng vẫn nên bắt thêm mã 128
  ở tầng 2 (phòng khi BE đổi mức mà client chưa cập nhật) — báo "vượt hạn mức", không gợi ý
  đổi sang PIN vì PIN cũng bị chặn ở cùng ngưỡng.
- **Việc cần làm thêm (không có trong mục 6):** `WithdrawView.swift:34` đang tự khai
  `private static let maxAmountPerWithdraw: Int64 = 10_000_000` — cùng con số, cùng ý
  nghĩa (`limitFace`), nhưng `private` và độc lập với chỗ này. Trước khi thêm
  `QuickTransferIntent`, gộp về **1 hằng số chung** (ví dụ `TransferLimits.faceFixed` ở
  file mới `Services/TransferLimits.swift`) rồi cho cả `WithdrawView` và
  `QuickTransferIntent` dùng lại — không hardcode `10_000_000` thêm lần thứ 2 độc lập,
  đúng bài học đã gặp ở phần Quick Action (2 chuỗi type độc lập không ai canh khớp).

## 8. Đã code — quyết định phát sinh khác bản thiết kế gốc

Mục 1-7 ở trên là bản thiết kế BAN ĐẦU, giữ nguyên làm tài liệu tham khảo. Lúc code thật
phát sinh vài điểm cần chốt thêm hoặc sửa lại vì thiết kế gốc chưa khớp hết với BE/API thật:

1. **Tầng 1 (mục 1, dòng "ký & chuyển hoàn toàn chạy ngầm") ĐÃ SỬA LẠI logic xác thực.**
   Đối chiếu `be/src/modules/wallet/wallet.service.ts` dòng 616 xác nhận: `amount < limitPin`
   thì `transferToWallet` **THỰC THI NGAY**, không tạo pending — nên **không có
   `transactionId`** để gọi `verify-transfer-biometric` (endpoint đó chỉ dùng được khi có
   giao dịch pending). Quyết định chốt: Face ID ở tầng 1 là **lớp chặn phía CLIENT**
   (`LAContext.evaluatePolicy`), KHÔNG ký gì, KHÔNG gọi `BiometricService` — đúng cách UI app
   xử lý giao dịch dưới `limitPin` (không hiện `PinEntrySheet`/`BiometricAuthSheet`, chuyển
   thẳng). Đánh đổi: Face ID tầng này chỉ chặn được ai KHÔNG bypass được `LAContext` (không
   phải xác thực có BE verify) — chấp nhận được vì tầng 1 giới hạn số tiền nhỏ (`limitPin`,
   mặc định 500k) và tầng 2/3 vẫn xác thực đầy đủ.

2. **Không tin `limitPin` đã đọc lúc đầu `perform()` cho tới cuối.** Giữa lúc Siri nghe câu
   lệnh và lúc thực sự chạy `perform()` (có thể vài giây tới vài phút nếu Siri disambiguate),
   user có thể đã hạ `limitPin` ở máy khác. BE luôn là nơi quyết định cuối — sau khi gọi
   `transferToWallet`, PHẢI kiểm `result.isPending`: nếu BE bất ngờ trả pending (đáng lẽ tầng 1
   không pending), báo lỗi rõ "cần mở app xác nhận thêm", TUYỆT ĐỐI không báo "đã chuyển" khi
   `isPending == true` — tiền chưa đi, và ngữ cảnh Siri không có UI để xử lý PIN/Face ID tiếp.

3. **Framework `AppIntents` không cần khai trong `.pbxproj`.** Đối chiếu cách project hiện
   dùng `AVFoundation`/`Vision`/`LocalAuthentication` (đều KHÔNG xuất hiện trong
   `PBXFrameworksBuildPhase`, chỉ các xcframework tuỳ chỉnh như CmcEkycSDK mới cần khai) —
   system framework thuần chỉ cần `import`, Xcode tự link. Mục 6 việc-4 ("thêm framework") có
   thể bỏ qua, chưa xác nhận build thật vì máy code không có Xcode.

4. **`LAContext.evaluatePolicy` bọc thủ công bằng `withCheckedContinuation`**, không dựa vào
   async overload tự sinh của compiler cho completion-handler API — không có SDK tại chỗ để
   xác nhận Swift có tự sinh `async throws` cho API này hay không, nên chọn cách chắc chắn
   đúng bất kể (cùng pattern `SpeechRecognizerService.swift:111` đã dùng trong project).

5. **Gộp hằng số `10_000_000` rộng hơn phạm vi mục 7 nêu** — ngoài `WithdrawView`, còn
   `BankTransferView.maxAmountPerTransfer`, `WalletTransferAmountView.maxAmountPerTransfer`
   (3 chỗ dùng), và `LinkedBanksView` (dòng hiển thị). Tất cả đã gộp về
   `TransferLimits.faceFixed`.

6. **File chưa build/test.** Toàn bộ `Services/Intents/WalletContactEntity.swift` +
   `QuickTransferIntent.swift` viết không có SDK `AppIntents` tại chỗ để compile-check —
   `entities(matching:)`/`entities(for:)` chắc chắn đúng chữ ký (protocol requirement), nhưng
   `suggestedEntities()` cần verify khi build lần đầu (có default no-op, không phải lỗi
   nghiêm trọng nếu Xcode báo không override được gì).
