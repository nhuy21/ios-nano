# Nano-Ewallet (iOS / Swift)

Ví điện tử native iOS

- **Bundle ID:** `vn.casso.nano`
- **Deployment target:** iOS 16.0
- **Swift:** 5.0, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (mọi type không đánh dấu
  `nonisolated` đều ngầm định MainActor)
- **Project format:** `PBXFileSystemSynchronizedRootGroup` (Xcode 16+) — thêm file mới vào
  thư mục là Xcode tự nhận, **không cần sửa** `.pbxproj`

## Chạy lần đầu

1. **Lấy SDK eKYC** — 3 xcframework không nằm trong git, thiếu là không build được.
   Xem [`Frameworks/README.md`](Frameworks/README.md).
2. **Thêm Firebase SPM package**: File > Add Package Dependencies >
   `https://github.com/firebase/firebase-ios-sdk` > chọn product **FirebaseMessaging**.
3. **Cấu hình biến môi trường**: copy `.env.example` thành `.env`, điền `BE_BASE_URL`.
   `Scripts/env-to-xcconfig.sh` sinh xcconfig từ file này.
4. **Signing & Capabilities**: bật **Push Notifications**, **Associated Domains**,
   **Near Field Communication Tag Reading**. File `.entitlements` đã có nội dung, nhưng Xcode
   cần bật capability mới gắn đúng vào target lúc build.
5. **Universal Links**: host `apple-app-site-association` tại
   `https://nano.casso.dev/.well-known/apple-app-site-association`

## Cấu trúc

```
nano ewallet/
├── App/                  # nano_ewalletApp (entry), AppDelegate (Firebase, push, Quick Action), AppState
├── Navigation/           # NavGraph, RootNavigator (cây theo AppRootState), Route (enum route từng tab)
├── Core/
│   ├── AppConfig         # đọc BE_BASE_URL từ xcconfig
│   ├── Network/          # APIClient (envelope {success,statusCode,message,data}), APIError, TokenRefresher
│   ├── Storage/          # KeychainStore, BiometricKeyStore (Secure Enclave), BiometricTokenStore
│   └── Extensions/       # AmountParser, SpeechAmountParser, VietQrBuilder, Int+VND, View+OnChangeCompat
├── Models/               # DTO mirror be/src (Auth, Transfer, Biometric, MoneyRequest, Beneficiary...)
├── Services/             # 1 service / 1 nhóm endpoint + các *Store (ObservableObject) giữ state
│   └── Intents/          # App Intents cho Siri (QuickTransferIntent, WalletContactEntity)
├── Ekyc/                 # EkycLauncher (mở SDK CMC), EkycSessionManager, EkycUploader, EkycPermissions
├── UI/
│   ├── Screens/          # auth, onboarding, main, transfer, history, contacts, settings
│   ├── Components/       # sheet/dialog/field dùng chung
│   └── Theme/            # AppColor, Typography (BeVietnamPro)
├── Data/                 # TransactionModel, TransactionRepository
├── Info.plist            # quyền camera/mic/speech/NFC/FaceID, URL scheme, Quick Actions, UIAppFonts
└── nano ewallet.entitlements
```

## Services/

Mỗi file phụ trách đúng 1 nhóm endpoint BE hoặc 1 mảng state riêng. Các `*Store` là
`ObservableObject` singleton (`.shared`) giữ state dùng chung nhiều màn; các `*Service` chỉ
gọi API, không giữ state.

| File | Vai trò |
| --- | --- |
| `AuthService.swift` | API login/register/OTP/quên mật khẩu |
| `AuthStore.swift` | Lưu phiên đăng nhập (token, deviceId) trong Keychain |
| `AccountService.swift` | API đổi mật khẩu, PIN, hạn mức |
| `BankService.swift` | Cache danh sách ngân hàng (`BankCache`) + parse QR (`banks/parse-qr`) |
| `BeneficiaryService.swift` | API CRUD danh bạ thụ hưởng |
| `BeneficiaryStore.swift` | State danh bạ cho UI (in-memory, observable) |
| `BiometricService.swift` | Face ID/Touch ID: ký giao dịch (Secure Enclave) + mở khoá đăng nhập |
| `DeepLinkStore.swift` | Điều hướng Universal Link/URL scheme/push/Siri/Quick Action vào đúng màn — xem [Deep link](#deep-link--url-scheme) |
| `HistoryStore.swift` | State + phân trang màn Lịch sử giao dịch |
| `MoneyRequestService.swift` | API "yêu cầu tiền"/cuộc trò chuyện (`money-requests`) |
| `NetworkMonitor.swift` | Theo dõi kết nối mạng (`NWPathMonitor`) |
| `NotificationPrefs.swift` | Cờ tuỳ chọn thông báo của user (lưu local) |
| `NotificationService.swift` | API danh sách thông báo trong app |
| `NotificationStore.swift` | State thông báo (badge, danh sách) |
| `OnboardingService.swift` | API eKYC/liên kết ví Bảo Kim: trạng thái, embed link, xác thực CCCD |
| `OneTouchResolver.swift` | Suy ra người nhận từ clipboard/ảnh (QR, SMS ngân hàng, số ví) |
| `PayLinkService.swift` | API tạo/resolve link nhận tiền (`pay-links`) |
| `PushRegistrar.swift` | Đăng ký token push (APNs qua Firebase) |
| `SpeechRecognizerService.swift` | Nhận diện giọng nói on-device (chuyển tiền bằng giọng nói) |
| `SpeechService.swift` | Parse văn bản nhận diện được thành số tiền/ý định |
| `TextRecognizer.swift` | OCR bằng Vision (ảnh chụp tin nhắn chuyển khoản) |
| `TransactionService.swift` | API danh sách/chi tiết giao dịch (cursor pagination) |
| `TransactionStore.swift` | State giao dịch (observable) |
| `TransferLimits.swift` | Hằng số hạn mức chuyển tiền (PIN vs Face ID) — xem [Ngưỡng giao dịch](#ngưỡng-giao-dịch) |
| `TransferService.swift` | API chuyển tiền: `verify-beneficiary`, `transfer-to-wallet`, `transfer-to-bank`, `verify-transfer` |
| `TtsAnnouncer.swift` | Đọc thông báo bằng giọng nói (text-to-speech) |
| `VoiceCommandResolver.swift` | Parse lệnh giọng nói thành bản nháp người nhận + số tiền |
| `WalletService.swift` | API thông tin ví (`getMyWallet`) |
| `WalletStore.swift` | State số dư/thông tin ví (observable) |

## UI/Screens/

- **auth/** — `SplashView` (khởi động, kiểm tra phiên), `LoginView`/`LoginViewModel`,
  `RegisterView`/`RegisterViewModel`, `OtpView`/`OtpViewModel` (xác thực OTP),
  `ForgotPasswordView`/`ForgotPasswordViewModel`, `WelcomeBackView`/`WelcomeBackViewModel`
  (đăng nhập nhanh cho user quay lại), `DeviceOtpDialogs` (OTP thiết bị lạ).
- **onboarding/** — `WalletOnboardingChoiceView` (liên kết ví Bảo Kim có sẵn hay tạo mới),
  `CccdScanView` (quét CCCD), `KycReviewView` (xem lại field eKYC), `FixEkycFieldsView`
  (sửa field bị từ chối), `WalletRulesView` (điều khoản), `AgreementWebView` (webview hợp
  đồng), `WalletLinkBaoKimView`/`WalletLinkingWebView` (webview liên kết Bảo Kim),
  `OnboardingLoadingView` (poll trạng thái tạo ví), `WalletLinkErrorView` (màn lỗi).
- **main/** — `MainTabView` (khung tab bar), `HomeView` (trang chủ: số dư, lối vào tính
  năng), `SettingsView` (menu Cá nhân), `NotificationsView`, `VoiceCommandOverlay` (UI
  chuyển tiền bằng giọng nói).
- **transfer/** — `WalletTransferAmountView` (nhập số tiền chuyển ví-ví), `BankTransferView`
  (form chuyển khoản ngân hàng), `WithdrawView` (rút về ngân hàng), `QrScanView`/
  `QrScanNavigationView` (quét QR), `ReceiveQrView` (hiện QR nhận tiền của mình),
  `ConversationView` (cuộc trò chuyện yêu cầu tiền), `TransferSuccessView` (biên lai thành
  công).
- **history/** — `HistoryView` (danh sách giao dịch), `DateFilterSheet` (lọc theo khoảng
  ngày).
- **contacts/** — `ContactsView` (danh sách), `ContactActionSheet`, `AddContactSheet`,
  `EditNicknameSheet`.
- **settings/** — `SecurityView` (trung tâm bảo mật), `ChangePasswordView`/ViewModel,
  `PinLimitView`/ViewModel (PIN & hạn mức), `DevicesView`/ViewModel (thiết bị/phiên đã liên
  kết), `LinkedBanksView`, `BiometricSettingsSection`, `TermsOfUseView`.

## Luồng onboarding (đăng ký -> có ví dùng được)

```
Đăng ký (RegisterView)
  -> Xác thực OTP (OtpView, AuthService)
  -> Chọn liên kết ví Bảo Kim có sẵn hay tạo mới (WalletOnboardingChoiceView)
  -> Quét CCCD (CccdScanView)
  -> Xem lại / sửa field eKYC (KycReviewView, FixEkycFieldsView, OnboardingService)
  -> Điều khoản + hợp đồng điện tử (WalletRulesView, AgreementWebView)
  -> Webview liên kết Bảo Kim + OTP Bảo Kim (WalletLinkBaoKimView, WalletLinkingWebView)
  -> Poll trạng thái tạo ví READY/PENDING (OnboardingLoadingView, OnboardingService)
  -> (nếu lỗi) WalletLinkErrorView
  -> HomeView với ví đã sẵn sàng dùng
```

## Các luồng chuyển tiền

| Luồng | Màn hình vào | Service |
| --- | --- | --- |
| Ví -> Ví | `UI/Screens/transfer/WalletTransferAmountView.swift` | `TransferService.verifyBeneficiary` + `transfer-to-wallet` |
| Chuyển khoản ngân hàng | `UI/Screens/transfer/BankTransferView.swift` | `TransferService.transfer-to-bank`, tra cứu qua Bảo Kim (`verify-beneficiary`) hoặc VietQR (`BankService`) tuỳ màn |
| Rút tiền về ngân hàng | `UI/Screens/transfer/WithdrawView.swift` | `TransferService`/endpoint rút tiền |
| Link nhận tiền / QR | `QrScanView.swift` + `QrScanNavigationView.swift` (quét), `ReceiveQrView.swift` (tạo QR nhận) | `PayLinkService.swift` |
| OneTouch (tự nhận diện clipboard/ảnh) | Kích hoạt từ `HomeView.swift`/`MainTabView.swift` | `OneTouchResolver.swift` (dùng `TextRecognizer` OCR + `BankService` parse QR) |
| Chuyển tiền bằng giọng nói / Siri | `VoiceCommandOverlay.swift` | `VoiceCommandResolver.swift`, `Services/Intents/QuickTransferIntent.swift` (App Intent Siri) — xem [`docs/siri-quick-transfer.md`](docs/siri-quick-transfer.md) |

## Deep link / URL scheme

`DeepLinkStore` nhận diện và điều hướng các nguồn sau:

- **Pay link**: `nanowallet://pay` (custom scheme) hoặc `https://nano.casso.dev/pay...`
  (Universal Link), đọc query `req_token` để resolve qua `PayLinkService`.
- **Push `MONEY_REQUEST`**: mở màn `ConversationView` với đúng `bkUsername` gửi kèm payload.
- **Cold start không có deep link nào**: mặc định mở màn quét QR.
- **Home Screen Quick Action** `vn.casso.nano.shortcut.walletTransfer` — mở chuyển tiền ví
  (nhập tay).
- **Home Screen Quick Action** `vn.casso.nano.shortcut.bankTransfer` — mở chuyển khoản ngân
  hàng.
- **Siri `QuickTransferIntent`** (mức 2, số tiền giữa `limitPin` và `limitFace`) — điền sẵn
  `WalletTransferDraft` để user xác nhận trước khi gửi.

## Mapping quyền (Android -> iOS)

| Android (AndroidManifest.xml) | iOS |
| --- | --- |
| `CAMERA` | `NSCameraUsageDescription` |
| `RECORD_AUDIO` | `NSMicrophoneUsageDescription` |
| `RecognitionService` query | `NSSpeechRecognitionUsageDescription` |
| `USE_BIOMETRIC` | `NSFaceIDUsageDescription` |
| `NFC` / `uses-feature nfc` | `NFCReaderUsageDescription` + `com.apple.developer.nfc.readersession.formats` (**entitlements**) **và** `...iso7816.select-identifiers` (**Info.plist**, KHÔNG phải entitlements — xem ghi chú trong `.entitlements`) — đọc chip CCCD qua ISO7816 nên phải khai cả AID |
| `POST_NOTIFICATIONS` | `UNUserNotificationCenter.requestAuthorization` (`PushRegistrar`) + `UIBackgroundModes: remote-notification` + `aps-environment` |
| `INTERNET` / `ACCESS_NETWORK_STATE` | Không cần khai — theo dõi qua `NWPathMonitor` (`NetworkMonitor`) |
| App Links (`nano.casso.dev/pay`) | Universal Links qua `com.apple.developer.associated-domains` |
| Custom scheme `nanowallet://pay` | `CFBundleURLTypes` |
| `res/xml/shortcuts.xml` | `UIApplicationShortcutItems` (Info.plist) + `AppDelegate` |
| FCM (`MyFirebaseMessagingService`) | `FirebaseMessaging` + `MessagingDelegate` trong `AppDelegate` |

## Xác thực sinh trắc (Face ID / Touch ID)

Hai cơ chế độc lập, bật/tắt riêng trong **Cá nhân > Mật khẩu**:

- **Đăng nhập** — BE cấp token dài hạn (90 ngày, gia hạn theo lần dùng), client giữ trong
  Keychain có ACL sinh trắc. KHÔNG lưu mật khẩu trên máy. Nút chỉ hiện ở `WelcomeBackView`
  (số điện thoại đã lưu), không có ở màn đăng nhập tài khoản khác.
- **Xác thực giao dịch** — khoá ECDSA P-256 sinh trong Secure Enclave, private key không rời
  khỏi chip. Ký `SHA256("txId|amount|recipient|deviceId")` để BE dựng lại và verify — sửa số
  tiền/người nhận sau khi quét mặt sẽ làm chữ ký sai (dynamic linking, PSD2).

Chi tiết: `BiometricKeyStore`, `BiometricTokenStore`, `BiometricService`,
`be/src/modules/wallet/biometric.service.ts`.

## Ngưỡng giao dịch

| Ngưỡng | Giá trị | Nguồn |
| --- | --- | --- |
| `limitPIN` | mặc định 500.000đ, user tự hạ được | `wallets.limitPIN`, theo từng user |
| `limitFace` | 10.000.000đ, cố định mọi user | `TransferLimits.faceFixed` |

Dưới `limitPIN`: BE thực thi ngay. Từ `limitPIN` trở lên: BE trả `{pending, transactionId}`,
client phải xác thực tiếp (mật khẩu 6 số hoặc chữ ký sinh trắc) rồi gọi `verify-transfer`.
Trên `limitFace`: Bảo Kim từ chối (mã 128).

## Chuyển tiền nhanh qua Siri

Người dùng nói *"Hey Siri, chuyển 5 nghìn cho A trên Ví nano"* — mức độ "chạy ngầm hoàn
toàn" hay "phải mở app xác nhận" phụ thuộc số tiền, chia đúng 3 tầng theo 2 ngưỡng sẵn có
(`limitPin`/`limitFace`, xem [Ngưỡng giao dịch](#ngưỡng-giao-dịch) ở trên), không phát sinh
ngưỡng riêng cho Siri:

| Số tiền | Hành vi |
| --- | --- |
| `amount ≤ limitPin` | Siri đọc lại xác nhận 1 lần → Face ID (overlay hệ thống) → chuyển **hoàn toàn chạy ngầm**, không mở app. |
| `limitPin < amount ≤ limitFace` | **Mở app**, vào thẳng màn xác nhận đã điền sẵn người nhận/số tiền (`Route.walletTransferAmount`) — người dùng tự xem lại rồi xác nhận như luồng thường. |
| `amount > limitFace` | Không chuyển được bằng cách nào — báo lỗi "vượt hạn mức", dừng ngay, không mở app. |

**Chạy trong tiến trình app chính, không cần Widget Extension riêng** — App Intents gọi từ
Siri/Shortcuts được hệ thống launch app ở chế độ nền (không hiện UI) để chạy `perform()`,
cùng container nên đọc được Keychain và gọi thẳng service hiện có (`BeneficiaryStore`,
`BiometricService`, `TransferService`), không cần target mới hay App Group.

**2 intent, không phải 1** — `AppIntent.openAppWhenRun` là static property theo KIỂU
intent, không đổi động theo `amount` lúc chạy được, nên tách:

- `QuickTransferIntent` — expose ra Siri qua `AppShortcutsProvider`, LUÔN chạy ngầm, tự
  quyết định có handoff sang intent mở app hay không.
- `QuickTransferOpenAppIntent` — không có `phrases` riêng, chỉ được gọi qua
  `.result(opensIntent:)` khi vào tầng 2, `openAppWhenRun = true` ép hệ thống mở app trước
  khi `perform()` chạy.

**Bảo mật tầng 1 (chạy ngầm)**: đối chiếu `be/src/modules/wallet/wallet.service.ts`,
`amount < limitPin` thì `transferToWallet` **thực thi ngay, không tạo pending** — nên không
có `transactionId` để ký qua `BiometricService`/`verify-transfer-biometric` (endpoint đó chỉ
dùng được khi có giao dịch pending). Face ID ở tầng này là **lớp chặn phía CLIENT**
(`LAContext.evaluatePolicy`), không ký gì, không có nhánh fallback về PIN — chấp nhận được
vì tầng 1 giới hạn đúng số tiền nhỏ (`limitPin`, mặc định 500.000đ), tầng 2/3 vẫn xác thực
đầy đủ qua màn hình app. BE luôn là nơi quyết định cuối: sau khi gọi `transferToWallet` phải
kiểm `result.isPending` — nếu BE bất ngờ trả pending, báo lỗi "cần mở app xác nhận thêm",
tuyệt đối không báo "đã chuyển" khi tiền chưa thực sự đi.

**Ánh xạ danh bạ → entity Siri** (`Services/Intents/WalletContactEntity.swift`):
`Beneficiary` có 2 tên khác nhau cho cùng 1 người (`nickname` do user tự đặt, `accName` tên
thật do BE trả) — tìm kiếm bằng giọng nói phải khớp cả hai, và `subtitle` hiển thị phải
khác `name` (ưu tiên ngược lại nhau) để Siri phân biệt được khi trùng tên, không đọc lại
disambiguation với 2 lựa chọn nghe giống hệt nhau.

Chi tiết đầy đủ, các quyết định phát sinh lúc code, và giới hạn/rủi ro đã biết:
[`docs/siri-quick-transfer.md`](docs/siri-quick-transfer.md).

## Bảo mật màn hình nền (App Switcher)

`UI/Components/PrivacyScreenOverlay.swift` che kín màn hình (nền brand + logo) ngay khi
`scenePhase` rời `.active` (kể cả `.inactive`, không chỉ `.background`) — iOS chụp ảnh
snapshot để làm thẻ preview App Switcher đúng lúc đó, không hỏi ý app. Không che thì số
dư/số tài khoản/giao dịch thật lộ ra cho bất kỳ ai cầm máy đã mở khoá, không cần mở app.
Gắn ở gốc `nano_ewalletApp.swift`, dùng `.transition(.identity)` để ẩn/hiện tức thì, không
delay qua animation.

## Khác biệt theo phiên bản iOS

| Tính năng | iOS 16 – 18.3 | iOS 18.4+ | iOS 26+ |
| --- | --- | --- | --- |
| Giọng nói nhập số tiền | `SFSpeechRecognizer` (qua server Apple, cần mạng) | như trái | `SpeechAnalyzer` on-device, không cần mạng |
| Shortcut Siri trong app Shortcuts | Ẩn | Hiện | Hiện |
| "Hey Siri, chuyển 5 nghìn cho…" | Không (Siri chưa có tiếng Việt) | Có | Có |
| Quick Action long-press icon | Có | Có | Có |

Tiếng Việt **không có** model on-device trên `SFSpeechRecognizer`
(`supportsOnDeviceRecognition == false` cho `vi-VN`) — giới hạn của Apple, không phải cấu hình
app. `SpeechAnalyzer` (iOS 26) khắc phục được; `HomeView` gọi
`SpeechRecognizerService.prewarmModel()` để tải trước model, tránh người dùng bấm mic rồi
phải chờ tải.

`View+OnChangeCompat.swift` là lớp tương thích duy nhất còn lại: `.onChange(of:initial:)` hai
tham số là iOS 17+, cao hơn deployment target. Mọi nơi trong app phải gọi qua
`.onChangeCompat(...)`/`.onChangeNewCompat(...)`, không gọi thẳng `.onChange(of:)` của
SwiftUI — xem comment trong file để biết vì sao closure phải ghi rõ label `perform:`.

## Testing

Hiện chưa có test target nào (không có thư mục/target Unit Tests hay UI Tests).

## Scripts/

- `Scripts/env-to-xcconfig.sh` — sinh `Config.xcconfig` từ `.env` (Xcode không hỗ trợ đọc
  `.env` trực tiếp). Chạy tay hoặc gắn làm Run Script Phase trước khi build.

## Tài liệu thiết kế

- [`docs/siri-quick-transfer.md`](docs/siri-quick-transfer.md) — chuyển tiền nhanh qua Siri:
  3 tầng theo `limitPin`/`limitFace`, quyết định đã chốt và các đánh đổi.

## Quy ước khi viết code

- `Models/` và `Services/` **mirror đúng** DTO/flow ở `be/src` — không tự thêm logic phụ.
- BE trả BIGINT dưới dạng String. Riêng `result.data` của Bảo Kim được truyền thẳng và
  **không nhất quán kiểu** (số/chuỗi lẫn lộn) — xem `TransferResult.init(from:)`.
- Interceptor của BE **bỏ hẳn** field `data` khi giá trị null, nên endpoint giao dịch coi
  "2xx nhưng thiếu `data`" là thành công rỗng (`APIError.missingData`).
- Font dùng chung một họ **BeVietnamPro** qua `AppFont.beVietnamPro(_:_:)`. `.system(size:)`
  chỉ dành cho `Image(systemName:)` (SF Symbols).
- Mọi màn tự vẽ header/nút back riêng (mirror Android) nên phải gắn
  `.hidesSystemNavigationBar()` cho **từng** màn, cả root lẫn destination.
