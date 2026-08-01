//
//  ActionChooserSheet.swift
//  nano ewallet
//
//  Port Dialog "Nạp/Rút ví" + hàng `PasteSourceRow` trong HomeScreen.kt — thẻ trắng bo
//  góc, tiêu đề + phụ đề, rồi các dòng thao tác có icon tròn và mô tả.
//
//  Android KHÔNG dùng menu hệ thống ở đây, nên iOS cũng không dùng confirmationDialog
//  (menu đó chỉ có mỗi tiêu đề nút, mất hẳn phần icon và dòng mô tả).
//

import SwiftUI

struct ActionChooserSheet: View {
    let title: String
    let subtitle: String
    let actions: [Action]
    let onDismiss: () -> Void

    struct Action: Identifiable {
        let id = UUID()
        let systemImage: String
        let title: String
        let subtitle: String
        let handler: () -> Void
    }

    private static let brand = Color(hex: 0x00A85E)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(AppFont.beVietnamPro(16, .bold))
                .foregroundStyle(AppColor.payInk)
                .padding(.horizontal, 20)

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(AppColor.payMuted)
                .padding(.horizontal, 20)
                .padding(.vertical, 2)

            Spacer().frame(height: 10)

            ForEach(actions) { action in
                Button {
                    onDismiss()
                    action.handler()
                } label: {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(Self.brand.opacity(0.12))
                            .frame(width: 40, height: 40)
                            .overlay {
                                Image(systemName: action.systemImage)
                                    .font(.system(size: 20))
                                    .foregroundStyle(Self.brand)
                            }

                        VStack(alignment: .leading, spacing: 0) {
                            Text(action.title)
                                .font(AppFont.beVietnamPro(14, .semibold))
                                .foregroundStyle(AppColor.payInk)
                            Text(action.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(AppColor.payMuted)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
        )
    }
}
