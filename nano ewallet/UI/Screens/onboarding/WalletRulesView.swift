//
//  WalletRulesView.swift
//  nano ewallet
//
//  Mirror WalletRulesScreen.kt — màn quy tắc giao dịch, hiện MỘT LẦN ngay sau khi
//  onboarding thành công (cả luồng tạo ví eKYC lẫn liên kết ví Bảo Kim), trước khi vào
//  Home. Chỉ mang tính thông báo; các con số khớp với ràng buộc phía backend/Bảo Kim
//  (>= 500k cần PIN, tối đa 10tr/giao dịch, 20tr/ngày = code 130, 100tr/tháng = code 131).
//
//  Chặn back để buộc người dùng đọc rồi bấm "Đã hiểu, bắt đầu sử dụng".
//

import SwiftUI

struct WalletRulesView: View {
    let onStart: () -> Void
    var onAdjustLimit: () -> Void = {}

    /// Chiều cao safe area trên (tai thỏ / Dynamic Island). Đọc qua `connectedScenes` thay
    /// `UIScreen.main` (deprecated iOS 26); không có scene thì rơi về 47pt (Dynamic Island).
    private static var topSafeInset: CGFloat {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let inset = scene?.windows.first { $0.isKeyWindow }?.safeAreaInsets.top
            ?? scene?.windows.first?.safeAreaInsets.top
        return inset ?? 47
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 8 chứ không phải 28 như Android: ScrollView của iOS đã tự chèn sẵn
                    // một khoảng lề trên, cộng đủ 28 nữa là hụt hẫng cả một mảng trắng.
                    Spacer().frame(height: 8)

                    Circle()
                        .strokeBorder(AppColor.payInputBorder, lineWidth: 1.5)
                        .frame(width: 64, height: 64)
                        .overlay {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(AppColor.brand)
                        }

                    Spacer().frame(height: 18)

                    Text("Vài điều cần biết")
                        .font(AppFont.beVietnamPro(22, .bold))
                        .foregroundStyle(AppColor.payInk)

                    Spacer().frame(height: 8)

                    Text("Để bảo vệ tài khoản, giao dịch của bạn áp dụng các quy tắc dưới đây:")
                        .font(AppFont.beVietnamPro(14))
                        .foregroundStyle(AppColor.payMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer().frame(height: 24)

                    ruleCard(
                        icon: "lock.fill",
                        title: "Xác thực giao dịch",
                        desc: """
                        Dưới 500.000đ: chuyển ngay, không cần xác nhận.
                        Từ 500.000đ trở lên: cần nhập mã PIN.

                        Mặc định ngưỡng là 500.000đ. Bạn có thể điều chỉnh ngưỡng xuống ngay tại đây, \
                        hoặc chỉnh sau trong mục Cá nhân → Ngưỡng xác thực PIN.
                        """,
                        actionLabel: "Điều chỉnh ngưỡng ngay",
                        onAction: onAdjustLimit
                    )

                    Spacer().frame(height: 12)

                    ruleCard(
                        icon: "creditcard.fill",
                        title: "Mỗi giao dịch",
                        desc: "Chuyển tối đa 10.000.000đ cho một lần giao dịch."
                    )

                    Spacer().frame(height: 12)

                    ruleCard(
                        icon: "calendar",
                        title: "Trong ngày",
                        desc: "Tổng chuyển tối đa 20.000.000đ mỗi ngày."
                    )

                    Spacer().frame(height: 12)

                    ruleCard(
                        icon: "calendar.badge.clock",
                        title: "Trong tháng",
                        desc: "Tổng chuyển tối đa 100.000.000đ mỗi tháng."
                    )

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 24)
                // ScrollView của iOS 26 cho nội dung chạy ngầm dưới thanh trạng thái
                // (hiệu ứng mép cuộn). Không chặn thì vòng tròn icon đè lên đồng hồ/pin —
                // mirror `statusBarsPadding()` bên Android.
                //
                // `.safeAreaPadding` là iOS 17, cao hơn deployment target, nên chèn đệm
                // thủ công. Đặt trên NỘI DUNG chứ không trên `ScrollView`: đặt ngoài thì
                // đệm nằm ngoài vùng cuộn, cuộn lên nội dung vẫn trượt vào status bar.
                .padding(.top, Self.topSafeInset)
            }

            Button(action: onStart) {
                Text("Đã hiểu, bắt đầu sử dụng")
                    .font(AppFont.beVietnamPro(16, .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(AppColor.brand, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .screenBackground(Color.white)
        // Chặn quay lại: luồng onboarding đã xong, không có đường lùi.
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled()
    }

    private func ruleCard(
        icon: String,
        title: String,
        desc: String,
        actionLabel: String? = nil,
        onAction: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(AppColor.payInputBorder, lineWidth: 1)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(AppColor.brand)
                }

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(AppFont.beVietnamPro(15, .semibold))
                    .foregroundStyle(AppColor.payInk)

                Spacer().frame(height: 4)

                // Không thêm lineSpacing: BeVietnamPro 13pt đã có chiều cao dòng ~18pt,
                // đúng bằng lineHeight bên Android. Cộng thêm là chữ rời rạc, thẻ phình to.
                Text(desc)
                    .font(AppFont.beVietnamPro(13))
                    .foregroundStyle(AppColor.payMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionLabel, let onAction {
                    Spacer().frame(height: 10)
                    Button(action: onAction) {
                        Text("\(actionLabel) →")
                            .font(AppFont.beVietnamPro(13, .bold))
                            .foregroundStyle(AppColor.brand)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppColor.payInputBorder, lineWidth: 1)
        }
    }
}

#Preview {
    WalletRulesView(onStart: {})
}
