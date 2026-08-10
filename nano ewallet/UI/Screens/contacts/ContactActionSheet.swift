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
                actionRowCustomIcon(
                    title: "Cấp cứu ví tui", icon: .requestMoney, tint: AppColor.brand, action: onRequest
                )
            }

            actionRow(title: "Đổi tên gợi nhớ", systemImage: "pencil", tint: AppColor.payInk, action: onEditNickname)

            actionRow(title: "Xoá khỏi danh bạ", systemImage: "trash", tint: Color(hex: 0xE5484D), action: onDelete)

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 20)
        // Sheet không set nền sẽ lấy nền hệ thống — ở dark mode là ĐEN, mà chữ trong đây
        // đều là màu tối cố định (`payInk`/`payMuted`) nên bị dìm gần như không đọc được.
        // Ghim nền sáng cho khớp Android (bên đó nền sheet là `Color.White` cứng).
        //
        // Phải giãn hết khung TRƯỚC khi tô nền: `VStack` chỉ cao bằng nội dung, mà detent
        // cố định thường cao hơn — tô nền theo `VStack` sẽ để hở dải dưới lộ lại nền đen.
        // `alignment: .top` giữ nội dung ở trên, không bị dồn ra giữa khi giãn.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
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
            // Không có `contentShape` thì `Spacer()` bên phải không nhận chạm — bấm vào
            // khoảng trống cạnh chữ là không ăn.
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }

    /// "Cấp cứu ví tui" — icon vẽ tay từ Android (ic_request_money), không phải Material Icon.
    private func actionRowCustomIcon(
        title: String, icon: TransactionIconKind, tint: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                TransactionIcon(kind: icon, tint: tint)
                    .frame(width: 18, height: 18)
                    .frame(width: 24)
                Text(title)
                    .font(AppFont.beVietnamPro(15))
                    .foregroundStyle(tint)
                Spacer()
            }
            .padding(.vertical, 14)
            // Không có `contentShape` thì `Spacer()` bên phải không nhận chạm — bấm vào
            // khoảng trống cạnh chữ là không ăn.
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}
