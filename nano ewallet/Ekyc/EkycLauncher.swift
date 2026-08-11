//
//  EkycLauncher.swift
//  nano ewallet
//
//  Mirror `startCmcEkyc` + `launchSdk` trong MainActivity.kt — dựng cấu hình rồi mở SDK
//  CmcEkyc.
//
//  Chạy với `isUseCmcGateway = false`: SDK KHÔNG tự đẩy kết quả qua gateway CMC, mà trả
//  ảnh mặt trước/sau CCCD, ảnh khuôn mặt và dữ liệu chip NFC thô qua `rawDataDelegate`.
//  App tự chịu trách nhiệm gửi lên backend Nano — giống hệt cách Android đang chạy.
//
//  SDK là UIKit nên phải mượn view controller đang hiển thị; SwiftUI không mở thẳng được.
//

import SwiftUI
import UIKit
import CmcEkycSDK

/// Nhận dữ liệu thô từ SDK và đổ vào `PendingKyc` — tương ứng `CmcRawDataCollector.kt`.
final class EkycRawDataCollector: NSObject, CmcRawDataDelegate {

    func handleNFCData(jsonNfc: [String: Any]) {
        Task { @MainActor in
            PendingKyc.shared.nfcRaw = jsonNfc
        }
    }

    func handleLivenessData(faceImageBase64String: String, variant: String) {
        Task { @MainActor in
            PendingKyc.shared.livenessPortraitBase64 = faceImageBase64String
        }
    }

    func handleCaptureData(isFront: Bool, idCardImageBase64String: String) {
        Task { @MainActor in
            if isFront {
                PendingKyc.shared.frontImageBase64 = idCardImageBase64String
            } else {
                PendingKyc.shared.backImageBase64 = idCardImageBase64String
            }
        }
    }
}

@MainActor
enum EkycLauncher {

    /// Giữ delegate sống suốt phiên — SDK chỉ giữ tham chiếu yếu (`AnyObject`), thả ra là
    /// mất sạch ảnh và dữ liệu NFC mà không báo lỗi gì.
    private static var rawDataCollector: EkycRawDataCollector?

    enum LaunchError: LocalizedError {
        case noSession(String)
        case noViewController

        var errorDescription: String? {
            switch self {
            case .noSession(let message): return message
            case .noViewController: return "Không mở được màn xác thực, vui lòng thử lại"
            }
        }
    }

    /// Mở SDK. Phiên thường đã sẵn từ màn hướng dẫn; chưa sẵn thì chuẩn bị rồi mới mở.
    /// - Parameters:
    ///   - flow: `.nfcEkyc` = OCR + NFC + khuôn mặt (Android dùng chuỗi "nfc_ekyc").
    ///   - onCompleted: gọi khi SDK báo xong, kèm quyết định (`decision`) của CMC.
    ///   - onFailed: không mở được SDK / phiên hỏng.
    static func start(
        flow: CmcEkycFlowType = .nfcEkyc,
        onCompleted: @escaping (_ decision: String?) -> Void,
        onFailed: @escaping (_ message: String) -> Void
    ) async {
        let manager = EkycSessionManager.shared
        guard await manager.prepare() else {
            onFailed(manager.lastError ?? "Không khởi tạo được phiên xác thực")
            return
        }
        guard let session = manager.session else {
            onFailed("Không khởi tạo được phiên xác thực")
            return
        }
        guard let presenter = topViewController() else {
            onFailed(LaunchError.noViewController.localizedDescription)
            return
        }

        PendingKyc.shared.clear()
        let collector = EkycRawDataCollector()
        rawDataCollector = collector

        CmcEkycManager.shared.startEkyc(
            from: presenter,
            // false: tự gửi hồ sơ lên BE Nano thay vì để SDK đẩy qua gateway CMC.
            isUseCmcGateway: false,
            sessionCA: session.sessionCA,
            tokenCA: session.tokenCA,
            baseUrlCA: session.baseUrlCA,
            ekycSessionId: session.ekycSessionId,
            session: session.session ?? "",
            tokenCAKLP: session.tokenCAKala,
            baseUrl: session.baseUrl ?? "",
            language: "vi",
            mainColor: "#00A85E",
            btnTextColor: "#FFFFFF",
            backgroundColor: "#FFFFFF",
            isAnimatedBtn: true,
            isShowResultScreen: true,
            customerLanguage: nil,
            scanNFCTimeout: 180,
            livenessTimeout: 30,
            enableQRCode: false,
            livenessVersion: .passive,
            isOnlyShowReasonInResultVC: false,
            cornerRadiusBtn: 14,
            flowType: flow,
            mrz: nil,
            faceData: nil,
            onResult: { result in
                Task { @MainActor in
                    applyTextFields(from: result)
                    onCompleted(result?.decision)
                }
            },
            onEvent: { _ in },
            onShowError: { message, _ in
                Task { @MainActor in
                    onFailed(message ?? "Xác thực định danh gặp lỗi, vui lòng thử lại")
                }
            },
            errorScanNFCCallback: { _, description, retry, dismiss in
                Task { @MainActor in
                    presentNfcError(
                        on: presenter,
                        message: description ?? "Không đọc được chip trên thẻ, vui lòng thử lại",
                        retry: retry,
                        dismiss: dismiss
                    )
                }
            },
            rawDataDelegate: collector
        )
    }

    // MARK: - Private

    /// Ảnh do `rawDataDelegate` đổ vào; ở đây lấy phần chữ.
    ///
    /// Ưu tiên NFC (dữ liệu chip đã ký số, không sửa được), thiếu thì lấy từ OCR ảnh thẻ.
    /// Nhiều thẻ CCCD trả `dateOfIssuance` RỖNG từ chip — trường này vốn in ở mặt sau thẻ,
    /// chip không bắt buộc chứa. Chỉ đọc mỗi NFC thì nộp hồ sơ bị BE từ chối vì thiếu ngày
    /// cấp, mà người dùng không hiểu vì sao đã quét đủ mà vẫn lỗi.
    ///
    /// NƠI CẤP chỉ có ở OCR, chip không hề mang trường này.
    private static func applyTextFields(from result: CmcEkycResult?) {
        guard let result else { return }
        let nfc = result.nfcResult
        // Ngày cấp/nơi cấp in ở MẶT SAU nên đọc `backResult` trước; các trường còn lại
        // (tên, ngày sinh, số thẻ) nằm ở mặt trước.
        let back = result.backResult?.field
        let front = result.frontResult?.field
        let store = PendingKyc.shared

        func pick(_ values: String?...) -> String? {
            values.compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }

        store.idCardNumber = pick(nfc?.idNumber, front?.idNumber, back?.idNumber) ?? store.idCardNumber
        store.fullName = pick(nfc?.name, front?.name, back?.name) ?? store.fullName
        store.dateOfBirth = pick(nfc?.dateOfBirth, front?.birthday, back?.birthday) ?? store.dateOfBirth
        store.gender = pick(nfc?.gender, front?.gender, back?.gender) ?? store.gender
        store.address = pick(nfc?.address, front?.resident, back?.resident) ?? store.address
        store.issueDate = pick(nfc?.dateOfIssuance, back?.dateOfIssue, front?.dateOfIssue) ?? store.issueDate
        store.expireDate = pick(nfc?.dateOfExpiry, back?.dateOfExpiry, front?.dateOfExpiry) ?? store.expireDate
        store.placeOfIssues = pick(back?.placeOfIssue, front?.placeOfIssue) ?? store.placeOfIssues
    }

    /// Lỗi NFC do SDK bắn ra kèm hai closure — dựng hộp thoại để người dùng chọn thử lại
    /// hay thoát, giống Android.
    private static func presentNfcError(
        on presenter: UIViewController,
        message: String,
        retry: (() -> Void)?,
        dismiss: (() -> Void)?
    ) {
        let alert = UIAlertController(title: "Lỗi đọc chip NFC", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Thử lại", style: .default) { _ in retry?() })
        alert.addAction(UIAlertAction(title: "Thoát", style: .cancel) { _ in dismiss?() })
        (topViewController() ?? presenter).present(alert, animated: true)
    }

    /// View controller đang hiển thị trên cùng của scene đang hoạt động.
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first

        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
