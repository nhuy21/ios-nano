//
//  WalletOnboardingChoiceView.swift
//  nano ewallet
//
//  Mirror WalletOnboardingChoiceScreen.kt — thuần trình bày, không state/API.
//

import SwiftUI

struct WalletOnboardingChoiceView: View {
    let onBack: () -> Void
    let onSyncBaoKim: () -> Void
    let onCreateNewWallet: () -> Void
    var onContactSupport: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 8)

                BackHeader(action: onBack)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                Spacer().frame(height: 24)

                // TODO: thay Color.clear bằng Image("ic_vi") khi copy được asset.
                Color.clear.frame(width: 150, height: 150)

                Spacer().frame(height: 20)

                Text("Thông tin mở ví")
                    .font(AppFont.beVietnamPro(22, .heavy))
                    .foregroundStyle(AppColor.payInk)
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer().frame(height: 4)

                Text("Bạn muốn bắt đầu thế nào?")
                    .font(AppFont.beVietnamPro(14))
                    .foregroundStyle(AppColor.payMuted)
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer().frame(height: 28)

                baoKimCard

                Spacer().frame(height: 16)

                orDivider

                Spacer().frame(height: 16)

                newWalletCard

                Spacer().frame(height: 28)

                supportLink

                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 24)
        }
        .background(Color.white)
    }

    private var baoKimCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                // TODO: thay bằng Image("logo_baokim") khi copy được asset.
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(AppColor.brandSoft)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Đồng bộ từ ví Bảo Kim")
                        .font(AppFont.beVietnamPro(15, .bold))
                        .foregroundStyle(AppColor.payInk)
                    Text("Kết nối ví Bảo Kim hiện có của bạn.")
                        .font(AppFont.beVietnamPro(12))
                        .foregroundStyle(AppColor.payMuted)
                    Text("Giữ nguyên lịch sử giao dịch.")
                        .font(AppFont.beVietnamPro(12))
                        .foregroundStyle(AppColor.payMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColor.payMuted)
            }

            Text("Đã có tài khoản Bảo Kim")
                .font(AppFont.beVietnamPro(10, .semibold))
                .foregroundStyle(AppColor.brand)
                .frame(width: 168, height: 22)
                .background(AppColor.brandSoft)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.top, 12)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AppColor.payInputBorder, lineWidth: 1.5)
        }
        .inputShadow()
        .contentShape(Rectangle())
        .onTapGesture { onSyncBaoKim() }
    }

    private var orDivider: some View {
        HStack(spacing: 0) {
            Rectangle().fill(AppColor.payInputBorder).frame(height: 1)
            Text("HOẶC")
                .font(AppFont.beVietnamPro(12, .semibold))
                .foregroundStyle(AppColor.payMuted)
                .padding(.horizontal, 12)
            Rectangle().fill(AppColor.payInputBorder).frame(height: 1)
        }
    }

    private var newWalletCard: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(AppColor.brandSoft)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(AppColor.brand)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Chưa có ví")
                    .font(AppFont.beVietnamPro(15, .bold))
                    .foregroundStyle(AppColor.payInk)
                Text("Tạo Ví nano mới chỉ trong vài phút. Đơn giản, nhanh chóng, không rắc rối.")
                    .font(AppFont.beVietnamPro(12))
                    .foregroundStyle(AppColor.payMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundStyle(AppColor.payMuted)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color(hex: 0x784628).opacity(0x14 / 255.0), radius: 8, x: 0, y: 3)
        .contentShape(Rectangle())
        .onTapGesture { onCreateNewWallet() }
    }

    private var supportLink: some View {
        (
            Text("Cần trợ giúp?  ")
                .font(AppFont.beVietnamPro(13))
                .foregroundStyle(AppColor.payMuted)
            + Text("Liên hệ hỗ trợ")
                .font(AppFont.beVietnamPro(13, .bold))
                .foregroundStyle(AppColor.brand)
        )
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onContactSupport() }
    }
}

#Preview {
    WalletOnboardingChoiceView(onBack: {}, onSyncBaoKim: {}, onCreateNewWallet: {})
}
