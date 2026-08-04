//
//  BiometricService.swift
//  nano ewallet
//
//  Mirror be/src/modules/wallet/biometric.service.ts + phần sinh trắc của auth.service.ts.
//
//  Face ID KHÔNG gửi dữ liệu sinh trắc nào lên server. Hai cơ chế khác nhau:
//  - Xác thực giao dịch: Face ID mở khoá ký trong Secure Enclave, ký payload có SỐ TIỀN +
//    NGƯỜI NHẬN, BE verify chữ ký (dynamic linking — malware sửa payload sau khi quét mặt thì
//    chữ ký sai).
//  - Đăng nhập: Face ID mở Keychain lấy token dài hạn do BE cấp, đổi lấy session. KHÔNG lưu
//    mật khẩu trên máy.
//

import Foundation

enum BiometricService {

    private static var client: APIClient { .shared }
    private static var deviceId: String { AuthStore.shared.getOrCreateDeviceId() }

    // MARK: - Xác thực giao dịch

    /// Bật xác thực giao dịch bằng sinh trắc: sinh khoá trong Secure Enclave rồi đăng ký public
    /// key. Cần mật khẩu để chứng minh là chủ tài khoản (BE bắt buộc).
    ///
    /// Sinh khoá TRƯỚC khi gọi API nhưng chỉ giữ lại nếu API thành công — sai mật khẩu thì xoá
    /// khoá vừa sinh, không để lại khoá mồ côi mà BE không biết.
    static func enableForTransfer(password: String) async throws -> RegisterBiometricResult {
        let publicKey = try BiometricKeyStore.createKey()
        do {
            return try await client.request(
                .post, "wallet/biometric/register",
                body: RegisterBiometricRequest(
                    deviceId: deviceId,
                    publicKey: publicKey.base64EncodedString(),
                    password: password
                ),
                auth: true,
                as: RegisterBiometricResult.self
            )
        } catch {
            BiometricKeyStore.deleteKey()
            throw error
        }
    }

    /// `GET wallet/biometric/status`
    static func transferStatus() async throws -> BiometricStatus {
        try await client.request(
            .get, "wallet/biometric/status",
            query: ["deviceId": deviceId],
            auth: true,
            as: BiometricStatus.self
        )
    }

    /// Tắt: xoá khoá trên máy TRƯỚC, rồi gọi BE. Thứ tự này để nếu mạng lỗi thì máy đã hết ký
    /// được — thà BE còn public key mồ côi (vô hại, không ai ký nổi) hơn là ngược lại.
    static func disableForTransfer() async throws {
        BiometricKeyStore.deleteKey()
        try await client.requestVoid(
            .delete, "wallet/biometric", body: DeviceIdBody(deviceId: deviceId), auth: true
        )
    }

    /// Xác thực giao dịch pending bằng chữ ký sinh trắc — thay cho nhập mật khẩu 6 số.
    ///
    /// Payload ký PHẢI khớp từng ký tự với `signaturePayload()` bên BE:
    ///   "<transactionId>|<amount>|<recipient>|<deviceId>"
    /// `recipient` là số ví (chuyển ví) hoặc số tài khoản (chuyển ngân hàng/rút).
    static func verifyTransfer(
        transactionId: String,
        amount: Int64,
        recipient: String
    ) async throws -> TransferResult {
        let payload = "\(transactionId)|\(amount)|\(recipient)|\(deviceId)"
        let signature = try BiometricKeyStore.sign(
            payload: payload,
            reason: "Xác nhận chuyển tiền"
        )

        do {
            return try await client.request(
                .post, "wallet/verify-transfer-biometric",
                body: VerifyTransferBiometricRequest(
                    transactionId: transactionId,
                    deviceId: deviceId,
                    signature: signature.base64EncodedString()
                ),
                auth: true, slow: true,
                as: TransferResult.self
            )
        } catch APIError.missingData(_) {
            // Giống các endpoint giao dịch khác: BE bỏ hẳn field `data` khi Bảo Kim trả null,
            // nhưng tiền ĐÃ trừ. Coi là thành công rỗng, xem TransferService.performTransfer.
            return .empty
        }
    }

    // MARK: - Đăng nhập

    /// Bật đăng nhập bằng sinh trắc: BE cấp token dài hạn, lưu vào Keychain có ACL sinh trắc.
    /// Token GỐC chỉ nhận được một lần nên phải ghi ngay.
    static func enableForLogin(password: String) async throws {
        let result = try await client.request(
            .post, "auth/biometric/register",
            body: RegisterBiometricLoginRequest(deviceId: deviceId, password: password),
            auth: true,
            as: RegisterBiometricLoginResult.self
        )
        guard BiometricTokenStore.save(result.biometricToken) else {
            // Không ghi được Keychain -> huỷ luôn phía BE, không để trạng thái lệch
            // (BE nghĩ đã bật, máy thì không có token nên không đăng nhập được).
            try? await disableForLogin()
            throw BiometricKeyError.failed("Không lưu được thông tin đăng nhập sinh trắc")
        }
    }

    /// Đăng nhập bằng sinh trắc — đọc token qua Face ID rồi đổi lấy session.
    /// Trả về `AuthOutcome` y như login thường: BE vẫn có thể đòi OTP thiết bị nếu máy khác
    /// đang đăng nhập (sinh trắc KHÔNG phải đường vòng né OTP).
    static func loginWithBiometric() async throws -> AuthService.AuthOutcome {
        guard let token = BiometricTokenStore.read(reason: "Đăng nhập vào Ví nano") else {
            throw BiometricKeyError.keyMissing
        }
        return try await AuthService.loginWithBiometricToken(token)
    }

    /// Tắt đăng nhập sinh trắc. Xoá token trên máy trước (xem `disableForTransfer`).
    static func disableForLogin() async throws {
        BiometricTokenStore.remove()
        try await client.requestVoid(
            .post, "auth/biometric/remove", body: DeviceIdBody(deviceId: deviceId), auth: true
        )
    }

    /// Máy này đã bật đăng nhập sinh trắc chưa — chỉ kiểm tra có token, KHÔNG bật Face ID.
    static var hasLoginToken: Bool { BiometricTokenStore.exists() }
}
