//
//  WalletContactEntity.swift
//  nano ewallet
//
//  Ánh xạ Beneficiary (Models/BeneficiaryModels.swift) sang AppEntity cho Siri/Shortcuts —
//  xem docs/siri-quick-transfer.md mục 3.
//

import AppIntents

/// Người nhận trong danh bạ ví, hiển thị cho Siri chọn khi người dùng nói tên.
struct WalletContactEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Người nhận" }
    static var defaultQuery = WalletContactQuery()

    /// `Beneficiary.id` — dùng để tra lại bản ghi gốc lúc `perform()` chạy (có thể cách lúc
    /// nói vài giây/phút, danh bạ có thể đã đổi).
    let id: String
    /// Tên hiển thị — ưu tiên nickname, giống `Beneficiary.displayName`.
    let name: String
    /// Tên/số khác với `name` để Siri đọc disambiguation không bị trùng âm khi 2 người có
    /// cùng nickname (xem ghi chú ở `WalletContactQuery`).
    let subtitle: String
    /// `benUsername` thật — cần lại lúc tạo `WalletTransferDraft` để chuyển tiền, KHÔNG
    /// phải `id` của bản ghi danh bạ.
    let benUsername: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(subtitle)")
    }
}

// LƯU Ý BUILD: file này được viết KHÔNG có SDK AppIntents để compile-check tại chỗ (máy dev
// hiện tại không cài Xcode). `entities(matching:)`/`entities(for:)` là requirement chắc chắn
// của `EntityStringQuery`/`EntityQuery`. `suggestedEntities()` là override của `EntityQuery`
// (có default no-op) — nếu Xcode báo lỗi "does not override" thì xoá override đó, không phải
// lỗi nghiêm trọng (Siri vẫn chạy được, chỉ mất gợi ý sẵn khi chưa gõ gì).
struct WalletContactQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [WalletContactEntity] {
        let all = await BeneficiaryStore.shared.get()
        return all.compactMap { Self.makeEntity(from: $0) }
            .filter { entity in
                entity.name.localizedCaseInsensitiveContains(string)
                    || entity.subtitle.localizedCaseInsensitiveContains(string)
            }
    }

    func entities(for identifiers: [String]) async throws -> [WalletContactEntity] {
        let all = await BeneficiaryStore.shared.get()
        return all.filter { identifiers.contains($0.id) }.compactMap { Self.makeEntity(from: $0) }
    }

    func suggestedEntities() async throws -> [WalletContactEntity] {
        // Không sort theo useCount ở đây — BeneficiaryStore không đảm bảo thứ tự đó, và Siri
        // tự xếp theo tần suất dùng shortcut của chính người dùng qua thời gian.
        let all = await BeneficiaryStore.shared.get()
        return all.compactMap { Self.makeEntity(from: $0) }
    }

    /// Chỉ nhận danh bạ loại VÍ — Siri intent này chỉ chuyển ví-ví (xem
    /// `QuickTransferIntent`), người thụ hưởng ngân hàng không có `benUsername` để chuyển.
    ///
    /// `subtitle` PHẢI khác `name` để Siri đọc disambiguation nghe ra khác biệt khi trùng
    /// tên (mục 3 trong doc thiết kế): `name` ưu tiên nickname nên `subtitle` ưu tiên NGƯỢC
    /// LẠI — tên thật/số ví.
    private static func makeEntity(from beneficiary: Beneficiary) -> WalletContactEntity? {
        guard beneficiary.type == .wallet,
              let benUsername = beneficiary.benUsername, !benUsername.isEmpty else { return nil }

        let name = beneficiary.displayName
        let subtitle = beneficiary.nickname != nil
            ? (beneficiary.accName ?? benUsername)
            : benUsername

        return WalletContactEntity(
            id: beneficiary.id, name: name, subtitle: subtitle, benUsername: benUsername
        )
    }
}
