# nano ewallet (iOS / Swift)

Native iOS app.

## Cấu trúc thư mục

```
nano ewallet/
├── App/                 # nano_ewalletApp.swift (entry), AppDelegate.swift
├── Navigation/           # NavGraph.kt -> NavGraph.swift
├── UI/
│   ├── Screens/          # ui/screens/*.kt -> *.swift (MainScreen.swift đã có sẵn)
│   ├── Components/       # ui/components/*.kt -> *.swift
│   └── Theme/            # ui/theme/*.kt -> *.swift
├── Services/             # services/*.kt -> *.swift (PushRegistrar, DeepLinkStore, NetworkMonitor...)
├── Ekyc/                 # ekyc/*.kt -> *.swift
├── Data/                 # data/*.kt -> *.swift (models, repositories)
├── Util/                 # util/*.kt -> *.swift (trống, thêm khi cần)
├── Info.plist            # permissions (camera, mic, speech, NFC, url scheme)
└── nano ewallet.entitlements  # associated domains, push, NFC
```

Project dùng **PBXFileSystemSynchronizedRootGroup** (Xcode 16+)

## Mapping quyền (Android -> iOS)

| Android (AndroidManifest.xml)      | iOS                                                          |
|-------------------------------------|---------------------------------------------------------------|
| `CAMERA`                             | `NSCameraUsageDescription` (Info.plist)                        |
| `RECORD_AUDIO`                       | `NSMicrophoneUsageDescription` (Info.plist)                     |
| `RecognitionService` query            | `NSSpeechRecognitionUsageDescription` (Info.plist)               |
| `NFC` / `uses-feature nfc`           | `NFCReaderUsageDescription` (Info.plist) + `com.apple.developer.nfc.readersession.formats` (entitlements) |
| `POST_NOTIFICATIONS`                 | `UNUserNotificationCenter.requestAuthorization` (`PushRegistrar.swift`) + `UIBackgroundModes: remote-notification` + `aps-environment` (entitlements) |
| `INTERNET` / `ACCESS_NETWORK_STATE`  | Không cần khai báo — theo dõi qua `NWPathMonitor` (`NetworkMonitor.swift`) |
| App Links (`nano.casso.dev/pay`)     | Universal Links qua `com.apple.developer.associated-domains` (entitlements) |
| Custom scheme `nanowallet://pay`     | `CFBundleURLTypes` (Info.plist)                                 |
| FCM (`MyFirebaseMessagingService`)   | `FirebaseMessaging` + `MessagingDelegate` trong `AppDelegate.swift` (đã viết sẵn — **cần thêm SPM package**, xem dưới) |

## Firebase

- **Bundle ID: `com.nanowallet.app`** — phải khớp `BUNDLE_ID` trong `GoogleService-Info.plist`,
  Firebase project: `nanocasso26`.
- Code trong `AppDelegate.swift` / `PushRegistrar.swift` đã `import FirebaseCore` +
  `FirebaseMessaging` → **project chưa build được cho tới khi thêm SPM package**:

  File > Add Package Dependencies... > `https://github.com/firebase/firebase-ios-sdk`
  → chọn product **FirebaseMessaging** (tự kéo theo FirebaseCore).

## Việc cần làm tiếp trên Xcode (Mac)

1. Mở `nano ewallet.xcodeproj`.
2. Kiểm tra Signing & Capabilities: bật **Push Notifications** và **Associated Domains** cho target
   (file `.entitlements` đã có nội dung, nhưng Xcode cần bật capability thì mới tự thêm đúng vào target membership khi build).
3. Host file `apple-app-site-association` tại `https://nano.casso.dev/.well-known/apple-app-site-association`
   (tương đương `assetlinks.json` bên Android) để Universal Links hoạt động.
4. Thêm Firebase iOS SDK nếu cần FCM, rồi hoàn thiện `AppDelegate.swift` + `PushRegistrar.swift`.
5. Các file trong `Services/`, `Ekyc/`, `Data/` mới là khung (TODO) — khi implement phải mirror đúng
   DTO/flow ở `be/src`, không tự thêm logic phụ.
