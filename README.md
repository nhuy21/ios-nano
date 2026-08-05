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

## Mapping quyền (Android -> iOS)

| Android (AndroidManifest.xml) | iOS |
| --- | --- |
| `CAMERA` | `NSCameraUsageDescription` |
| `RECORD_AUDIO` | `NSMicrophoneUsageDescription` |
| `RecognitionService` query | `NSSpeechRecognitionUsageDescription` |
| `USE_BIOMETRIC` | `NSFaceIDUsageDescription` |
| `NFC` / `uses-feature nfc` | `NFCReaderUsageDescription` + `com.apple.developer.nfc.readersession.formats` **và** `...iso7816.select-identifiers` (entitlements) — đọc chip CCCD qua ISO7816 nên phải khai cả AID, xem `.entitlements` |
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
tham số là iOS 17+, cao hơn deployment target.

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

## Tài liệu thiết kế

- [`docs/siri-quick-transfer.md`](docs/siri-quick-transfer.md) — chuyển tiền nhanh qua Siri:
  3 tầng theo `limitPin`/`limitFace`, quyết định đã chốt và các đánh đổi.
