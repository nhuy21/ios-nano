//
//  SourceAccountCard.swift
//  nano ewallet
//
//  Thẻ "TK nguồn" đặt trên thẻ người nhận ở các màn chuyển tiền — gộp số ví nguồn
//  + số dư vào 1 khối, thay cho dòng "Số dư khả dụng" tách rời trước đây. Dùng
//  chung cho cả luồng chuyển ví (WalletTransferAmountView) và ngân hàng
//  (BankTransferView) nên số dư luôn hiển thị cùng một kiểu ở mọi màn.
//

import SwiftUI

struct SourceAccountCard: View {
    let username: String?
    let balance: Int64?

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(AppColor.brand)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "wallet.pass.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 4) {
                row(label: "TK nguồn", value: username ?? "—")
                row(label: "Số dư", value: balance.map { "\(Int($0).vndGrouped) VNĐ" } ?? "—")
            }
            Spacer()
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [AppColor.payBgTop, AppColor.payBgBottom],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppColor.brand.opacity(0.18), lineWidth: 1)
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text("\(label):")
                .font(AppFont.beVietnamPro(13))
                .foregroundStyle(AppColor.payMuted)
            Text(value)
                .font(AppFont.beVietnamPro(14, .bold))
                .foregroundStyle(AppColor.payInk)
                .lineLimit(1)
        }
    }
}
