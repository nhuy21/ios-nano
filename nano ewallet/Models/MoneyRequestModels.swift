//
//  MoneyRequestModels.swift
//  nano ewallet
//
//  Mirror be/src/modules/money-request/dto/money-request.dto.ts + MoneyRequestApi.kt.
//  amount là BIGINT ở BE -> trả String (như mọi số tiền khác trong app).
//

import Foundation

enum MoneyRequestStatus: String, Decodable {
    case pending = "PENDING"
    case approved = "APPROVED"
    case declined = "DECLINED"
    case cancelled = "CANCELLED"
    case expired = "EXPIRED"

    var label: String {
        switch self {
        case .pending: return "Đang chờ"
        case .approved: return "Đã chuyển"
        case .declined: return "Đã từ chối"
        case .cancelled: return "Đã huỷ"
        case .expired: return "Hết hạn"
        }
    }
}

/// 1 item trong timeline `GET money-requests/conversations/:otherBkUsername`.
struct MoneyRequestItem: Decodable, Identifiable {
    let id: String
    let amount: String
    let note: String?
    let status: MoneyRequestStatus
    let outgoing: Bool
    let expiresAt: String
    let createdAt: String
    let updatedAt: String

    var amountValue: Int64 { Int64(amount) ?? 0 }
}

struct MoneyRequestConversationOther: Decodable {
    let fullName: String?
    let bkUsername: String
}

/// `GET money-requests/conversations/:otherBkUsername`
struct MoneyRequestConversation: Decodable {
    let other: MoneyRequestConversationOther
    let items: [MoneyRequestItem]
}

/// `POST money-requests` — mirror CreateMoneyRequestDto (amount: Int, không phải String).
struct CreateMoneyRequestRequest: Encodable {
    let payerBkUsername: String
    let amount: Int
    var note: String?
}

/// Response `POST money-requests/:id/approve` — kèm `requesterBkUsername` để App biết
/// chuyển tiền cho ai ngay sau khi approve xong (BE KHÔNG tự chuyển tiền ở đây).
struct MoneyRequestApproveResult: Decodable {
    let id: String
    let status: MoneyRequestStatus
    let requesterBkUsername: String?
}

struct MoneyRequestSimpleResult: Decodable {
    let id: String
    let status: MoneyRequestStatus
}
