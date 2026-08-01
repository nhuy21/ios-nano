//
//  SupportDialog.swift
//  nano ewallet
//
//  Popup "Hỗ trợ khách hàng" — mirror Dialog compose trong WalletTransferAmountScreen.kt
//  (dòng 805-871): card TRẮNG CĂN GIỮA màn hình (không phải bottom sheet trượt đáy),
//  icon SupportAgent + số hotline to + nút "GỌI NGAY" pill xanh + nút "Đóng" text.
//

import SwiftUI
import UIKit

struct SupportDialog: View {
    var phone: String = "0966585328"
    let onDismiss: () -> Void

    private var formattedPhone: String {
        // "0966585328" -> "0966 585 328", mirror cách hiển thị WT_SUPPORT_PHONE bên Android.
        let digits = phone.filter(\.isNumber)
        guard digits.count == 10 else { return phone }
        let a = digits.prefix(4)
        let b = digits.dropFirst(4).prefix(3)
        let c = digits.suffix(3)
        return "\(a) \(b) \(c)"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 6) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 40))
                    .foregroundStyle(AppColor.brand)
                    .padding(.bottom, 4)

                Text("Hỗ trợ khách hàng")
                    .font(AppFont.beVietnamPro(16, .bold))
                    .foregroundStyle(AppColor.payInk)

                Text("Cần trợ giúp? Liên hệ tổng đài")
                    .font(AppFont.beVietnamPro(13))
                    .foregroundStyle(AppColor.payMuted)
                    .multilineTextAlignment(.center)

                Text(formattedPhone)
                    .font(AppFont.beVietnamPro(22, .bold))
                    .foregroundStyle(AppColor.brand)
                    .tracking(1)
                    .padding(.top, 2)
                    .padding(.bottom, 14)

                Button {
                    onDismiss()
                    if let url = URL(string: "tel://\(phone)") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("GỌI NGAY")
                        .font(AppFont.beVietnamPro(14, .bold))
                        .tracking(1)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(AppColor.brand)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    onDismiss()
                } label: {
                    Text("Đóng")
                        .font(AppFont.beVietnamPro(14, .semibold))
                        .foregroundStyle(AppColor.payMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 40)
        }
    }
}

#Preview {
    SupportDialog(onDismiss: {})
}
