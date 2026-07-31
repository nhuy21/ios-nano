//
//  ContactActionSheet.swift
//  nano ewallet
//

import SwiftUI

struct ContactActionSheet: View {
    let contact: Beneficiary
    let onTransfer: () -> Void
    let onRequest: () -> Void
    let onEditNickname: () -> Void
    let onDelete: () -> Void

    private var canRequest: Bool {
        contact.type == .wallet && !(contact.benUsername ?? "").isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(AppColor.line)
                .frame(width: 40, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 12)

            Text(contact.displayName)
                .font(AppFont.beVietnamPro(16, .bold))
                .foregroundStyle(AppColor.payInk)
                .padding(.bottom, 8)

            actionRow(title: "Chuyển tiền", systemImage: "paperplane.fill", tint: AppColor.brand, action: onTransfer)

            if canRequest {
                actionRow(title: "Cấp cứu ví tui", systemImage: "hand.raised.fill", tint: AppColor.brand, action: onRequest)
            }

            actionRow(title: "Đổi tên gợi nhớ", systemImage: "pencil", tint: AppColor.payInk, action: onEditNickname)

            actionRow(title: "Xoá khỏi danh bạ", systemImage: "trash", tint: Color(hex: 0xE5484D), action: onDelete)

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 20)
        .presentationDragIndicator(.hidden)
    }

    private func actionRow(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(tint)
                    .frame(width: 24)
                Text(title)
                    .font(AppFont.beVietnamPro(15))
                    .foregroundStyle(tint)
                Spacer()
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}
