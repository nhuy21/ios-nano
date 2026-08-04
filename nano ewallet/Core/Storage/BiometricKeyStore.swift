//
//  BiometricKeyStore.swift
//  nano ewallet
//
//  Khoá ký ECDSA P-256 nằm TRONG Secure Enclave — private key không bao giờ ra khỏi chip,
//  app chỉ xin chip ký hộ. Đây là cách các hệ thống ngân hàng làm: Face ID KHÔNG phải bí mật
//  gửi lên server, nó chỉ là điều kiện để được dùng khoá ký. Server giữ public key và verify
//  chữ ký (xem be/src/modules/wallet/biometric.service.ts).
//
//  Khác hẳn cách "Face ID mở Keychain lấy mật khẩu đã lưu": ở đây KHÔNG có mật khẩu nào nằm
//  trên thiết bị.
//

import Foundation
import LocalAuthentication
import Security

enum BiometricKeyError: LocalizedError {
    case notAvailable(String)
    case userCancelled
    case keyMissing
    case keyInvalidated
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable(let reason): return reason
        case .userCancelled: return "Đã huỷ xác thực"
        case .keyMissing: return "Thiết bị chưa bật xác thực sinh trắc"
        case .keyInvalidated: return "Face ID đã thay đổi, vui lòng bật lại trong Cài đặt"
        case .failed(let reason): return reason
        }
    }
}

nonisolated enum BiometricKeyStore {

    /// Tag của khoá trong Keychain (kSecClassKey). Cố định — mỗi app/thiết bị đúng 1 khoá.
    private static let keyTag = "dev.casso.nanowallet.biometric.signing".data(using: .utf8)!

    // MARK: - Khả dụng

    /// Loại sinh trắc máy đang có, để hiển thị đúng chữ "Face ID" hay "Touch ID".
    /// iPhone SE/iPad dùng Touch ID nên KHÔNG hard-code "Face ID".
    static var biometryLabel: String {
        switch LAContext().biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "Sinh trắc học"
        }
    }

    /// Máy có dùng được sinh trắc LÚC NÀY không. `nil` = dùng được; có giá trị = lý do không được.
    ///
    /// Phân biệt rõ hai trường hợp để báo đúng cho người dùng (yêu cầu của luồng Settings:
    /// toggle vẫn bấm được, bấm mới báo lỗi):
    /// - `.biometryNotEnrolled`: máy CÓ phần cứng nhưng chưa thiết lập -> hướng dẫn vào Cài đặt iOS
    /// - `.biometryNotAvailable`: máy không có phần cứng
    static func unavailableReason() -> String? {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            return nil
        }

        let label = biometryLabel
        switch LAError.Code(rawValue: error?.code ?? -1) {
        case .biometryNotEnrolled:
            return "Bạn chưa thiết lập \(label) trên máy. Vào Cài đặt > \(label) & Mật mã để thiết lập trước."
        case .biometryNotAvailable:
            return "Thiết bị này không hỗ trợ xác thực sinh trắc."
        case .biometryLockout:
            return "\(label) đang bị khoá do thử sai nhiều lần. Hãy mở khoá máy bằng mật mã rồi thử lại."
        case .passcodeNotSet:
            return "Bạn cần đặt mật mã cho máy trước khi dùng \(label)."
        default:
            return "Không dùng được \(label) lúc này."
        }
    }

    // MARK: - Khoá

    /// Khoá đã tồn tại trên máy này chưa.
    ///
    /// PHẢI kiểm tra bằng hàm này chứ không tin cờ lưu ở UserDefaults: xoá app rồi cài lại làm
    /// khoá trong Secure Enclave mất (khoá gắn với app), trong khi `deviceId` giữ trong Keychain
    /// nên BE vẫn thấy thiết bị "đã đăng ký" -> public key mồ côi. Không có khoá thì phải coi như
    /// chưa bật và đăng ký lại.
    static func hasKey() -> Bool {
        keyExists()
    }

    /// Sinh khoá mới trong Secure Enclave. Ghi đè khoá cũ nếu có (bật lại sau khi đổi Face ID).
    ///
    /// `.biometryCurrentSet`: thêm/đổi khuôn mặt trong Cài đặt iOS là khoá TỰ vô hiệu — chặn
    /// kịch bản kẻ có mật mã máy thêm khuôn mặt của mình vào rồi rút tiền. Dùng
    /// `.biometryAny` sẽ mất lớp bảo vệ này.
    ///
    /// `...ThisDeviceOnly`: không sync iCloud, không vào backup.
    static func createKey() throws -> Data {
        deleteKey()

        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet],
            &accessError
        ) else {
            throw BiometricKeyError.failed("Không tạo được điều kiện truy cập khoá")
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag,
                kSecAttrAccessControl as String: access,
            ],
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            let message = (error?.takeRetainedValue() as Error?)?.localizedDescription
                ?? "Không tạo được khoá bảo mật"
            throw BiometricKeyError.failed(message)
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            deleteKey()
            throw BiometricKeyError.failed("Không đọc được khoá công khai")
        }
        return try exportSPKI(publicKey)
    }

    static func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Ký

    /// Ký `payload` bằng khoá trong Secure Enclave — iOS TỰ hiện Face ID vì khoá có
    /// `.biometryCurrentSet`. Trả chữ ký ECDSA định dạng DER (khớp `dsaEncoding: 'der'` bên BE).
    ///
    /// - Parameter reason: dòng chữ hiện trong hộp thoại Face ID.
    static func sign(payload: String, reason: String) throws -> Data {
        guard let privateKey = loadPrivateKey(reason: reason) else {
            throw BiometricKeyError.keyMissing
        }

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            Data(payload.utf8) as CFData,
            &error
        ) as Data? else {
            throw Self.mapSignError(error?.takeRetainedValue() as Error?)
        }
        return signature
    }

    // MARK: - Private

    /// Đọc khoá riêng để ký. `reason` là dòng chữ hiện trong hộp thoại Face ID.
    ///
    /// `localizedFallbackTitle = ""` để ẩn nút "Nhập mật mã" của hệ thống: mật mã MÁY (6 số mở
    /// máy) không được phép thay cho xác thực giao dịch. Người dùng muốn dùng mật khẩu APP thì
    /// bấm nút "Dùng mật khẩu" trên sheet của mình.
    private static func loadPrivateKey(reason: String) -> SecKey? {
        let context = LAContext()
        context.localizedReason = reason
        context.localizedFallbackTitle = ""

        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
            kSecUseAuthenticationContext as String: context,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        // `as?` chứ KHÔNG `as!`: status thành công mà item sai kiểu là bất thường nhưng không
        // đáng crash app ví.
        return item as? SecKey
    }

    /// Khoá có tồn tại không, KHÔNG bật Face ID.
    ///
    /// Không dùng `loadPrivateKey()` được: với `interactionNotAllowed = true`, Keychain trả
    /// `errSecInteractionNotAllowed` (khoá CÓ nhưng cần xác thực mới lấy ref) — đó là thành công
    /// về mặt "tồn tại", nhưng `SecItemCopyMatching` không trả item nên kiểm theo ref sẽ ra sai.
    /// Vì vậy hỏi riêng bằng `kSecReturnAttributes` — chỉ đọc thuộc tính, không cần mở khoá.
    private static func keyExists() -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnAttributes as String: true,
            kSecUseAuthenticationContext as String: context,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        // errSecInteractionNotAllowed: khoá CÓ, chỉ là chưa xác thực -> vẫn là "đã bật".
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// Chuyển public key từ dạng thô X9.63 (65 byte, 0x04||X||Y) sang SPKI DER — định dạng mà
    /// `crypto.createPublicKey({ type: 'spki' })` bên BE đọc được, và cũng là định dạng Android
    /// KeyStore trả sẵn nên hai nền tảng gửi lên giống nhau.
    private static func exportSPKI(_ publicKey: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let raw = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw BiometricKeyError.failed("Không xuất được khoá công khai")
        }

        // Header SPKI cố định cho EC P-256 (prime256v1): SEQUENCE { AlgorithmIdentifier, BIT STRING }.
        // Với P-256 độ dài luôn cố định nên nhúng cứng được, không cần bộ mã hoá DER đầy đủ.
        let header: [UInt8] = [
            0x30, 0x59,                                                  // SEQUENCE, 89 byte
            0x30, 0x13,                                                  // SEQUENCE (AlgorithmIdentifier)
            0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,        // OID 1.2.840.10045.2.1 (ecPublicKey)
            0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07,  // OID 1.2.840.10045.3.1.7 (prime256v1)
            0x03, 0x42, 0x00,                                            // BIT STRING, 66 byte, 0 bit thừa
        ]
        guard raw.count == 65, raw.first == 0x04 else {
            throw BiometricKeyError.failed("Khoá công khai sai định dạng")
        }
        return Data(header) + raw
    }

    private static func mapSignError(_ error: Error?) -> BiometricKeyError {
        guard let error = error as NSError? else {
            return .failed("Không ký được giao dịch")
        }
        // Lỗi từ LocalAuthentication đi kèm qua CFError của SecKey.
        switch LAError.Code(rawValue: error.code) {
        case .userCancel, .systemCancel, .appCancel, .userFallback:
            return .userCancelled
        default:
            break
        }
        // Khoá bị vô hiệu vì đổi/thêm khuôn mặt (.biometryCurrentSet).
        if error.code == errSecItemNotFound || error.domain == NSOSStatusErrorDomain {
            return .keyInvalidated
        }
        return .failed(error.localizedDescription)
    }
}
