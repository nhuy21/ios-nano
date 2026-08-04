//
//  TransactionDetailSheet.swift
//  nano ewallet
//
//  Mirror TransactionDetailSheet.kt — dùng chung cho HomeView và HistoryView.
//

import SwiftUI

struct TransactionDetailSheet: View {
    let tx: TransactionEntity
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Capsule()
                    .fill(AppColor.line)
                    .frame(width: 40, height: 4)
                    .padding(.top, 8)

                let icon = TransactionDisplay.iconStyle(for: tx)
                TransactionIcon(kind: icon.icon, tint: icon.tint)
                    .frame(width: 40, height: 40)

                Text(signedAmount)
                    .font(AppFont.beVietnamPro(30, .heavy))
                    .foregroundStyle(TransactionDisplay.amountColor(for: tx))

                Text(TransactionDisplay.detailTitle(for: tx))
                    .font(AppFont.beVietnamPro(14, .semibold))
                    .foregroundStyle(AppColor.payInk)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                statusBadge

                Rectangle()
                    .fill(AppColor.line)
                    .frame(height: 1)
                    .padding(.top, 4)

                VStack(spacing: 0) {
                    detailRow(label: "Loại giao dịch", value: TransactionDisplay.typeLabel(for: tx))

                    if let name = tx.benAccName {
                        detailRow(label: tx.isIncome ? "Người gửi" : "Người nhận", value: name)
                    }

                    if let accNo = tx.benAccNo {
                        detailRow(label: tx.benBankName != nil ? "Số tài khoản" : "Số ví", value: accNo)
                    }

                    if let bankName = tx.benBankName {
                        detailRow(label: "Ngân hàng", value: bankName)
                    }

                    if let description = tx.description, !description.isEmpty {
                        detailRow(label: "Nội dung", value: description)
                    }

                    detailRow(label: "Thời gian", value: formattedTime)

                    detailRow(label: "Mã giao dịch", value: tx.bkTransId ?? tx.id)

                    detailRow(
                        label: "Phí giao dịch",
                        value: tx.feeValue > 0 ? Int(tx.feeValue).vndFormatted : "Miễn phí"
                    )

                    if let balanceAfter = tx.cachedBalanceAfterValue {
                        detailRow(label: "Số dư sau giao dịch", value: Int(balanceAfter).vndFormatted)
                    }
                }

                // Kích thước/nền phải nằm TRONG label kèm contentShape: để ở ngoài Button
                // thì vùng bấm chỉ là mấy chữ "Đóng", nền xanh chỉ là hình trang trí.
                Button {
                    onDismiss()
                } label: {
                    Text("Đóng")
                        .font(AppFont.beVietnamPro(15, .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(AppColor.brand)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .presentationDragIndicator(.hidden)
    }

    private var statusBadge: some View {
        let meta = TransactionDisplay.statusMeta(for: tx)
        return Text(meta.text)
            .font(AppFont.beVietnamPro(12, .semibold))
            .foregroundStyle(meta.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(meta.background)
            .clipShape(Capsule())
    }

    private func detailRow(label: String, value: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text(label)
                    .font(AppFont.beVietnamPro(13))
                    .foregroundStyle(AppColor.payMuted)
                    .frame(width: 130, alignment: .leading)
                Text(value)
                    .font(AppFont.beVietnamPro(13, .medium))
                    .foregroundStyle(AppColor.payInk)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 10)
            Divider()
        }
    }

    private var signedAmount: String {
        let signed = tx.isIncome ? tx.amountValue : -tx.amountValue
        return Int(signed).vndSigned
    }

    private var formattedTime: String {
        guard let date = ISO8601DateFormatter.withFractionalSeconds.date(from: tx.createdAt)
            ?? ISO8601DateFormatter.standard.date(from: tx.createdAt) else {
            return tx.createdAt
        }
        return DateFormatter.app("HH:mm • dd/MM/yyyy").string(from: date)
    }
}

#Preview {
    TransactionDetailSheet(
        tx: TransactionEntity(
            id: "abc123",
            type: "TRANSFER_IN",
            amount: "500000",
            fee: "0",
            description: "Chuyển tiền sinh nhật",
            cachedBalanceAfter: "12000000",
            bkTransId: "BK123456",
            benBankNo: nil,
            benAccNo: nil,
            benAccName: "Nguyễn Văn A",
            benBankName: nil,
            status: "SUCCESS",
            createdAt: "2026-07-31T10:24:00.000Z"
        ),
        onDismiss: {}
    )
}
