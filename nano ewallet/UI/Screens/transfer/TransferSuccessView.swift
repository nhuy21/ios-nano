//
//  TransferSuccessView.swift
//  nano ewallet
//
//  Mirror TransferSuccessScreen.kt / WalletTransferSuccessScreen.kt — dùng chung
//  cho cả 2 luồng (nội dung hiển thị giống hệt nhau, chỉ khác nhãn "Nội dung"/"Lời nhắn").
//

import SwiftUI

@MainActor
struct TransferSuccessView: View {
    let amount: Int64
    let recipientName: String
    let recipientDetail: String
    let noteLabel: String
    let note: String
    let onHome: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Circle()
                .fill(AppColor.brandSoft)
                .frame(width: 88, height: 88)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(AppColor.brand)
                }

            Text("Chuyển tiền thành công")
                .font(AppFont.beVietnamPro(19, .bold))
                .foregroundStyle(AppColor.payInk)
                .padding(.top, 20)

            Text(Int(amount).vndFormatted)
                .font(AppFont.baloo2(30, .bold))
                .foregroundStyle(AppColor.brand)
                .padding(.top, 6)

            VStack(spacing: 0) {
                detailRow(label: "Người nhận", value: recipientName)
                Divider()
                detailRow(label: recipientDetail.isEmpty ? "Tài khoản" : "Chi tiết", value: recipientDetail)
                if !note.isEmpty {
                    Divider()
                    detailRow(label: noteLabel, value: note)
                }
            }
            .padding(.vertical, 4)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 24)

            Spacer()

            PrimaryButton(title: "Về trang chủ") {
                onHome()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(hex: 0xF7F8FA))
        .navigationBarBackButtonHidden(true)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppFont.beVietnamPro(13))
                .foregroundStyle(AppColor.payMuted)
            Spacer()
            Text(value)
                .font(AppFont.beVietnamPro(14, .semibold))
                .foregroundStyle(AppColor.payInk)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    TransferSuccessView(
        amount: 200_000, recipientName: "NGUYEN VAN A", recipientDetail: "Vietcombank • 0123456789",
        noteLabel: "Nội dung", note: "Chuyển tiền", onHome: {}
    )
}
