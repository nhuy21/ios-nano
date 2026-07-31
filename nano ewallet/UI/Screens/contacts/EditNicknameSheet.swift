//
//  EditNicknameSheet.swift
//  nano ewallet
//

import SwiftUI

struct EditNicknameSheet: View {
    let initialValue: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var value: String

    init(initialValue: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.initialValue = initialValue
        self.onSave = onSave
        self.onCancel = onCancel
        _value = State(initialValue: initialValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Capsule()
                .fill(AppColor.line)
                .frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            Text("Đổi tên gợi nhớ")
                .font(AppFont.beVietnamPro(17, .bold))
                .foregroundStyle(AppColor.payInk)

            Text("Ví dụ: Mẹ, Tiền nhà, Anh Nam...")
                .font(.system(size: 12))
                .foregroundStyle(AppColor.payMuted)

            AppTextField(
                text: $value,
                placeholder: "Tên gợi nhớ",
                submitLabel: .done,
                maxLength: 100
            )

            HStack(spacing: 12) {
                Button("Huỷ") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .font(AppFont.beVietnamPro(14, .semibold))
                .foregroundStyle(AppColor.payMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(hex: 0xF6F7F9))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button("Lưu") {
                    onSave(value.trimmingCharacters(in: .whitespaces))
                }
                .buttonStyle(.plain)
                .font(AppFont.beVietnamPro(14, .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppColor.brand)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.top, 8)
        }
        .padding(20)
        .presentationDragIndicator(.hidden)
    }
}
