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
                .font(AppFont.beVietnamPro(12))
                .foregroundStyle(AppColor.payMuted)

            AppTextField(
                text: $value,
                placeholder: "Tên gợi nhớ",
                submitLabel: .done,
                maxLength: 100
            )

            HStack(spacing: 12) {
                Button {
                    onCancel()
                } label: {
                    Text("Huỷ")
                        .font(AppFont.beVietnamPro(14, .semibold))
                        .foregroundStyle(AppColor.payMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(hex: 0xF6F7F9))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    onSave(value.trimmingCharacters(in: .whitespaces))
                } label: {
                    Text("Lưu")
                        .font(AppFont.beVietnamPro(14, .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColor.brand)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
        .padding(20)
        // Sheet không set nền sẽ lấy nền hệ thống — dark mode là ĐEN, mà chữ trong đây đều
        // là màu tối ghim cứng (`payInk`/`payMuted`) nên đen trên đen, không đọc được.
        // Giãn hết khung trước khi tô để không hở dải dưới (`VStack` chỉ cao bằng nội dung).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .presentationDragIndicator(.hidden)
    }
}
