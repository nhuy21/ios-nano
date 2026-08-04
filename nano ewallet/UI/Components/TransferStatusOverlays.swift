//
//  TransferStatusOverlays.swift
//  nano ewallet
//
//  Hai dialog chặn màn dùng chung cho mọi luồng chuyển tiền (ví / ngân hàng / rút),
//  mirror 2 `Dialog` trong TransferScreen.kt + WalletTransferAmountScreen.kt:
//
//   - `ProcessingOverlay`: chờ Bảo Kim xử lý. PHẢI chặn thao tác (không đóng được
//     bằng chạm ra ngoài) — bấm lại nút chuyển tiền lúc đang chờ có thể tạo lệnh
//     thứ hai. Bên Android là DialogProperties(dismissOnBackPress/ClickOutside=false).
//   - `TransferErrorOverlay`: giao dịch thất bại. Phải là dialog chứ không phải dòng
//     chữ đỏ cuối form — form cuộn được nên lỗi hiện dưới đáy sẽ không ai thấy, người
//     dùng tưởng bấm nút mà không có gì xảy ra.
//

import SwiftUI

struct ProcessingOverlay: View {
    var message: String = "Đang xử lý giao dịch..."

    var body: some View {
        ZStack {
            // Không gắn onTapGesture: chạm ra ngoài KHÔNG được đóng.
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .tint(AppColor.brand)
                    .scaleEffect(1.4)
                Text(message)
                    .font(AppFont.beVietnamPro(13.5, .medium))
                    .foregroundStyle(AppColor.payInk)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

struct TransferErrorOverlay: View {
    let message: String
    /// Bản Kotlin của luồng ngân hàng có icon cảnh báo, luồng ví thì không — giữ
    /// nguyên khác biệt đó thay vì tự thống nhất.
    var showIcon: Bool = true
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 6) {
                if showIcon {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(AppColor.error)
                        .padding(.bottom, 6)
                }

                Text("Giao dịch không thành công")
                    .font(AppFont.beVietnamPro(15, .bold))
                    .foregroundStyle(AppColor.payInk)

                Text(message)
                    .font(AppFont.beVietnamPro(13))
                    .foregroundStyle(AppColor.payMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                Button(action: onClose) {
                    Text("ĐÓNG")
                        .font(AppFont.beVietnamPro(14, .bold))
                        .tracking(1)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(AppColor.brand, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 40)
        }
    }
}
