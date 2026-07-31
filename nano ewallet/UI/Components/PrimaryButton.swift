//
//  PrimaryButton.swift
//  nano ewallet
//

import SwiftUI

/// Nút chính màu brand — mirror các nút "Đăng nhập"/"Tạo tài khoản" bên Android:
/// `fillMaxWidth`, shadow(8.3, r16, xanh 35%), clip(r16), `padding(vertical = 16.dp)`
/// (không set height cố định), chữ 16sp/w600/trắng.
///
/// Khi `isEnabled == false` hoặc `isLoading == true` thì nền mờ còn 60% alpha.
struct PrimaryButton: View {
    let title: String
    var loadingTitle: String?
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    private var tappable: Bool { isEnabled && !isLoading }

    var body: some View {
        Button(action: action) {
            Text(isLoading ? (loadingTitle ?? title) : title)
                .font(AppFont.beVietnamPro(16, .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AppColor.brand.opacity(tappable ? 1 : 0.6))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!tappable)
        .primaryButtonShadow()
    }
}

/// Nút back tròn ở góc trên trái + chữ "Quay lại" — dùng ở Register và WalletOnboardingChoice.
struct BackHeader: View {
    var label: String = "Quay lại"
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: action) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppColor.payInk)
                    .frame(width: 38, height: 38)
                    .background(Color.white)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .circleButtonShadow()
            .accessibilityLabel("Quay lại")

            Text(label)
                .font(AppFont.beVietnamPro(15, .medium))
                .foregroundStyle(AppColor.payMuted)

            Spacer(minLength: 0)
        }
    }
}

/// Dải phân cách "hoặc" — dùng ở Login và WelcomeBack.
struct OrDivider: View {
    var label: String = "hoặc"

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(AppColor.payDivider)
                .frame(height: 1)
            Text(label)
                .font(AppFont.beVietnamPro(12))
                .foregroundStyle(AppColor.payMuted)
                .padding(.horizontal, 16)
            Rectangle()
                .fill(AppColor.payDivider)
                .frame(height: 1)
        }
    }
}
