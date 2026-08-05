//
//  SecurityView.swift
//  nano ewallet
//
//  Mirror SecurityScreen.kt — tiêu đề thật trên UI là "Mật khẩu" (không phải
//  "Bảo mật & Mật khẩu" như label ở SettingsView). Thuần điều hướng, không API.
//

import SwiftUI

struct SecurityView: View {
    let onBack: () -> Void
    let onChangePassword: () -> Void
    let onDevicesClick: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(title: "Mật khẩu", onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Bảo mật")
                        .font(AppFont.beVietnamPro(13, .semibold))
                        .foregroundStyle(AppColor.payMuted)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        row(title: "Đổi mật khẩu", systemImage: "lock.fill", action: onChangePassword)
                        Rectangle().fill(AppColor.line).frame(height: 1).padding(.leading, 56)
                        row(title: "Thiết bị đã đăng nhập", systemImage: "iphone", action: onDevicesClick)
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color(hex: 0x784628).opacity(0x14 / 255.0), radius: 6, x: 0, y: 2)
                    // `BiometricSettingsSection` đã chuyển ra khối "Tài khoản" của màn Cá
                    // nhân — người dùng bật/tắt sinh trắc mà không phải vào sâu một màn nữa.
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 24) }
        }
        .background(Color(hex: 0xF7F8FA))
    }

    private func row(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(AppColor.payInk)
                    .frame(width: 28)
                Text(title)
                    .font(AppFont.beVietnamPro(15))
                    .foregroundStyle(AppColor.payInk)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.payMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
            // Không có `contentShape` thì `Spacer()` và phần `padding` (trong suốt) không
            // nhận chạm — phải bấm đúng chữ hoặc mũi tên mới mở được thẻ.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SecurityView(onBack: {}, onChangePassword: {}, onDevicesClick: {})
}
