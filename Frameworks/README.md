# Frameworks — SDK eKYC

Thư mục này **không nằm trong git** (xem `.gitignore`): ba xcframework cộng lại ~31MB
nhị phân, commit thẳng thì repo phình vĩnh viễn mỗi lần SDK lên phiên bản.

Clone dự án xong phải tự lấy về, thiếu là **không build được** (`FRAMEWORK_SEARCH_PATHS`
trỏ vào đây, target link và nhúng cả ba).

## Lấy về

```sh
git clone --depth 1 https://github.com/levanthanhlong/AppDemoEkycIos.git /tmp/ekycdemo
cp -R /tmp/ekycdemo/HelloSwiftUI/SDK/*.xcframework Frameworks/
find Frameworks -name ".DS_Store" -delete
```

Cần đúng ba thư mục sau:

| Framework | Vai trò |
|---|---|
| `CmcEkycSDK.xcframework` | SDK chính — `CmcEkycManager.shared.startEkyc(...)` |
| `KalapaSDK.xcframework` | Chụp/OCR CCCD và đọc chip NFC |
| `iProov.xcframework` | Xác thực khuôn mặt (liveness) |

## Vì sao là repo demo chứ không phải SPM/CocoaPods

Bản Android kéo `com.mobilecs:cmcekyc-sdk` từ
`maven.pkg.github.com/levanthanhlong/CmcEkyc-Sdk`. Cùng tác giả nhưng **bản iOS không
phát hành qua trình quản lý gói nào** — chỉ có xcframework nằm sẵn trong repo demo
`AppDemoEkycIos`. Muốn lên phiên bản mới thì kéo lại repo đó rồi chép đè.
