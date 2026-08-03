//
//  WalletLinkErrorView.swift
//  nano ewallet
//
//  Mirror WalletLinkErrorScreen.kt — Bảo Kim từ chối NGAY lúc gửi yêu cầu liên kết ví,
//  chưa tới bước OTP: ví không tồn tại, ví đang khoá, số điện thoại đã liên kết nơi khác,
//  tên không khớp thông tin đăng ký ví.
//
//  Là màn RIÊNG chứ không phải dòng chữ đỏ dưới ô nhập: mấy lỗi này người dùng không sửa
//  được bằng cách gõ lại, phải đi xử lý bên Bảo Kim rồi quay lại. Nhét vào form thì họ cứ
//  sửa tới sửa lui vô ích.
//

import SwiftUI

struct WalletLinkErrorView: View {

    /// Nội dung lỗi cụ thể do Bảo Kim trả về — phần duy nhất thay đổi giữa các loại lỗi.
    let message: String
    let onRetry: () -> Void
    let onLogout: () -> Void

    private enum Palette {
        static let title = Color(hex: 0xF1841F)
        static let subtitle = Color(hex: 0x827B7B)
        static let support = Color(hex: 0x5F6B66)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Spacer().frame(height: 60)

            Text("Liên kết ví thất bại!")
                .font(AppFont.beVietnamPro(24, .heavy))
                .foregroundStyle(Palette.title)
                .multilineTextAlignment(.center)

            Text(message)
                .font(AppFont.beVietnamPro(15, .light))
                .foregroundStyle(Palette.subtitle)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 8)

            // Co theo bề rộng màn thay vì cố định, để không tràn trên máy nhỏ.
            Image("mascot_sad")
                .resizable()
                .aspectRatio(288.0 / 289.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 60)
                .padding(.top, 24)

            retryButton
                .padding(.top, 24)

            Text("Vẫn không được? Liên hệ hỗ trợ")
                .font(AppFont.beVietnamPro(14, .semibold))
                .foregroundStyle(Palette.support)
                .padding(.top, 16)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
    }

    private var header: some View {
        HStack {
            Image("logo_green")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 86, height: 36)

            Spacer(minLength: 0)

            Button(action: onLogout) {
                Image("ic_logout_door")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .frame(width: 44, height: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Đăng xuất")
        }
        .padding(.leading, 22)
        .padding(.trailing, 22)
        .padding(.top, 14)
    }

    private var retryButton: some View {
        Button(action: onRetry) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                Text("Thử lại")
                    .font(AppFont.beVietnamPro(17, .heavy))
            }
            .foregroundStyle(.white)
            .frame(width: 272, height: 46)
            .background(AppColor.brand, in: Capsule())
        }
        .buttonStyle(.plain)
        .shadow(color: AppColor.brand.opacity(0x59 / 255.0), radius: 6, y: 3)
    }
}

#Preview {
    WalletLinkErrorView(
        message: "Số điện thoại này đã được liên kết với một ví khác. Vui lòng kiểm tra lại thông tin ví Bảo Kim của bạn.",
        onRetry: {}, onLogout: {}
    )
}
