//
//  BeneficiaryService.swift
//  nano ewallet
//
//  Mirror BeneficiaryApi.kt.
//

import Foundation
import Contacts

enum BeneficiaryService {
    /// `GET beneficiaries`
    static func list() async throws -> [Beneficiary] {
        try await APIClient.shared.request(.get, "beneficiaries", auth: true, as: [Beneficiary].self)
    }

    /// `POST beneficiaries/match-contacts` — gửi số điện thoại trong danh bạ máy, nhận về
    /// những người ĐANG có ví nano hoạt động.
    ///
    /// BE nhận tối đa 200 số mỗi lượt (`ArrayMaxSize`), nên nơi gọi phải tự chia lô.
    /// BE cũng tự chuẩn hoá số lần nữa — nó không tin dữ liệu client gửi.
    static func matchContacts(phones: [String]) async throws -> [MatchedFriend] {
        try await APIClient.shared.request(
            .post, "beneficiaries/match-contacts",
            body: MatchContactsRequest(phones: phones),
            auth: true, as: [MatchedFriend].self
        )
    }

    /// `POST beneficiaries`
    static func create(_ request: CreateBeneficiaryRequest) async throws -> Beneficiary {
        try await APIClient.shared.request(.post, "beneficiaries", body: request, auth: true, as: Beneficiary.self)
    }

    /// `PATCH beneficiaries/:id`
    static func updateNickname(id: String, nickname: String?) async throws -> Beneficiary {
        try await APIClient.shared.request(
            .patch, "beneficiaries/\(id)",
            body: UpdateBeneficiaryRequest(nickname: nickname),
            auth: true, as: Beneficiary.self
        )
    }

    /// `DELETE beneficiaries/:id`
    static func delete(id: String) async throws {
        try await APIClient.shared.requestVoid(.delete, "beneficiaries/\(id)", auth: true)
    }

    /// `POST beneficiaries/:id/touch` — best-effort, cập nhật lastUsedAt/useCount khi chọn dùng.
    static func touch(id: String) async {
        try? await APIClient.shared.requestVoid(.post, "beneficiaries/\(id)/touch", auth: true)
    }
}

// MARK: - Danh bạ máy

/// Một liên hệ trong danh bạ máy: tên người dùng tự lưu + số điện thoại đã chuẩn hoá.
struct PhoneContact {
    let name: String
    /// Dạng `0xxxxxxxxx` — đã bỏ khoảng trắng/dấu và quy `+84` về `0`.
    let phone: String
}

/// Đọc danh bạ MÁY để đối chiếu tìm bạn đã dùng nano.
///
/// ── ĐÂY LÀ DỮ LIỆU CỦA NGƯỜI THỨ BA ─────────────────────────────────────────────────────
/// Người dùng đồng ý cho đọc, nhưng những người TRONG danh bạ thì không đồng ý gì cả. Vì vậy:
///  - Chỉ đọc khi người dùng CHỦ ĐỘNG bấm tìm bạn, không đọc ngầm lúc mở app.
///  - Chỉ giữ trong bộ nhớ cho một lần đối chiếu; KHÔNG ghi ra đĩa, KHÔNG cache.
///  - Chỉ lấy đúng hai trường cần dùng (tên hiển thị + số), không lấy email/ảnh/ghi chú.
///  - Không bao giờ đưa số vào log.
///
/// ── CHUẨN HOÁ TRÙNG VỚI BACKEND ─────────────────────────────────────────────────────────
/// Backend cũng tự chuẩn hoá lần nữa — cố ý làm hai lần: chuẩn hoá ở client để BỎ TRÙNG trước
/// khi gửi (một người hay có 2-3 biến thể cùng số, gửi cả ba là tốn suất trong trần 200 số mỗi
/// lượt), còn backend thì không được tin dữ liệu client gửi. Hai bên phải CÙNG LUẬT — đổi một
/// bên thì đổi cả hai.
enum PhoneContacts {

    /// Chuẩn hoá số về dạng `0xxxxxxxxx`, trả `nil` nếu không phải số điện thoại VN dùng được.
    /// Cùng luật với backend: bỏ ký tự không phải chữ số, quy `+84`/`84` về `0`, thêm `0` cho
    /// số 9 chữ số.
    static func normalize(_ raw: String?) -> String? {
        let digits = (raw ?? "").filter(\.isNumber)
        guard !digits.isEmpty else { return nil }

        let normalized: String
        if digits.hasPrefix("84"), digits.count >= 10 {
            normalized = "0" + digits.dropFirst(2)
        } else if digits.hasPrefix("0") {
            normalized = digits
        } else if digits.count == 9 {
            normalized = "0" + digits
        } else {
            normalized = digits
        }

        let valid = normalized.count >= 9 && normalized.count <= 11 && normalized.hasPrefix("0")
        return valid ? normalized : nil
    }

    /// Quyền hiện tại, KHÔNG hỏi người dùng.
    static var authorizationStatus: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    /// Xin quyền đọc danh bạ. Trả `true` nếu được phép.
    ///
    /// Chỉ gọi khi người dùng đã bấm nút ở màn giải thích — bung hộp thoại hệ thống ngay lúc
    /// mở màn thì họ chưa biết app định làm gì với danh bạ nên dễ từ chối, mà iOS chỉ cho hỏi
    /// MỘT lần: từ chối rồi thì hộp thoại không hiện lại nữa, phải tự vào Cài đặt.
    static func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            CNContactStore().requestAccess(for: .contacts) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Toàn bộ liên hệ có số điện thoại dùng được, đã bỏ trùng theo số.
    ///
    /// Chưa có quyền thì trả rỗng chứ không ném lỗi: nơi gọi đã kiểm quyền trước, ném ở đây
    /// chỉ tạo thêm một đường lỗi phải bắt.
    static func readAll() async -> [PhoneContact] {
        guard authorizationStatus == .authorized else { return [] }

        return await withCheckedContinuation { continuation in
            // Danh bạ có thể vài nghìn dòng — đọc trên luồng nền để không khựng giao diện.
            DispatchQueue.global(qos: .userInitiated).async {
                // CHỈ xin đúng hai khoá cần dùng. `CNContactFetchRequest` bắt buộc khai trước
                // và ném lỗi nếu đọc khoá chưa khai, nên đây cũng là rào chắn kỹ thuật chống
                // vô tình chạm vào email/ảnh/ghi chú.
                let keys: [CNKeyDescriptor] = [
                    CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                    CNContactPhoneNumbersKey as CNKeyDescriptor,
                ]
                let request = CNContactFetchRequest(keysToFetch: keys)

                // `LinkedHashMap` bên Kotlin -> giữ thứ tự xuất hiện, bỏ trùng theo SỐ.
                var seen = Set<String>()
                var out: [PhoneContact] = []

                do {
                    try CNContactStore().enumerateContacts(with: request) { contact, _ in
                        let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
                        for number in contact.phoneNumbers {
                            guard let phone = normalize(number.value.stringValue),
                                  seen.insert(phone).inserted else { continue }
                            out.append(PhoneContact(name: name, phone: phone))
                        }
                    }
                } catch {
                    // Quyền bị thu hồi giữa chừng, hoặc kho danh bạ lỗi -> coi như không có.
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: out)
            }
        }
    }
}
