//
//  TransactionDetailView.swift
//  nano ewallet
//
//  Chi tiết giao dịch — mirror TransactionDetailScreen.kt. Trước đây là bottom sheet,
//  nay là màn riêng push vào `NavigationStack`: sheet không đủ chỗ cho biên lai và bị
//  thanh điều hướng hệ thống che mất nút Đóng ở cuối.
//

import SwiftUI
import UIKit

struct TransactionDetailView: View {
    let tx: TransactionEntity
    let onBack: () -> Void

    @StateObject private var toast = ToastState()

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(title: "Chi tiết giao dịch", onBack: onBack)
            content
        }
        .screenBackground(AppColor.bgSoft)
        .toast(toast, bottomPadding: 24)
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
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
                        detailRow(
                            label: tx.benBankName != nil ? "Số tài khoản" : "Số ví",
                            value: accNo,
                            copyable: true
                        )
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

                totalRow
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            // Nền phải phủ CẢ vùng cuộn, nên đặt `frame(maxWidth:)` + `background` lên nội
            // dung bên trong ScrollView: đặt ngoài ScrollView thì nội dung ngắn để hở phần
            // dưới, lộ lại nền hệ thống.
            .frame(maxWidth: .infinity)
            .background(AppColor.bgSoft)
        }
    }

    /// Số tiền + phí gộp lại — thứ người dùng thật sự bị trừ. Chỉ hiện ở giao dịch đi:
    /// giao dịch nhận không có phí nên dòng này lặp lại y hệt số tiền ở trên.
    @ViewBuilder
    private var totalRow: some View {
        if !tx.isIncome {
            HStack {
                Text("Tổng cộng")
                    .font(AppFont.beVietnamPro(14, .semibold))
                    .foregroundStyle(AppColor.payInk)
                Spacer(minLength: 0)
                Text(Int(tx.amountValue + tx.feeValue).vndFormatted)
                    .font(AppFont.beVietnamPro(16, .bold))
                    .foregroundStyle(AppColor.payInk)
            }
            .padding(.top, 4)
        }
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

    /// - Parameter copyable: có nút sao chép ở cuối hàng không. Chỉ bật cho những giá trị
    ///   người dùng thật sự cần chép lại (số ví, số tài khoản) — bật tràn lan thì hàng nào
    ///   cũng có icon, rối mà chẳng ai dùng.
    private func detailRow(label: String, value: String, copyable: Bool = false) -> some View {
        VStack(spacing: 0) {
            // Hàng có nút copy canh GIỮA: nút cao 32pt còn chữ chỉ ~16pt, canh `.top` sẽ
            // kéo nhãn/giá trị dính lên mép trên trong khi nút chiếm hết chiều cao hàng.
            // Hàng thường vẫn `.top` để nội dung dài nhiều dòng canh đúng mép trên như cũ.
            HStack(alignment: copyable ? .center : .top) {
                Text(label)
                    .font(AppFont.beVietnamPro(13))
                    .foregroundStyle(AppColor.payMuted)
                    .frame(width: 130, alignment: .leading)
                Text(value)
                    .font(AppFont.beVietnamPro(13, .medium))
                    .foregroundStyle(AppColor.payInk)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .multilineTextAlignment(.trailing)

                if copyable {
                    Button {
                        UIPasteboard.general.string = value
                        toast.show("Đã sao chép \(label.lowercased())")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColor.brand)
                            // Rộng ngang để dễ bấm, nhưng KHÔNG cao hơn chữ (20pt) — để
                            // 32pt thì riêng hàng này cao vống lên, lệch nhịp với các hàng
                            // còn lại. Phần chạm hụt bù bằng `padding(.vertical, 10)` của
                            // cả hàng, tổng vùng chạm vẫn ~40pt.
                            .frame(width: 32, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("Sao chép \(label.lowercased())")
                }
            }
            .padding(.vertical, 10)
            // Màu cố định thay `Divider()`: `Divider` lấy màu ngăn cách của hệ thống, đổi
            // theo light/dark mode nên trên nền sáng ghim cứng ở đây nó gần như tàng hình.
            // Khớp `SheetDivider` bên Android.
            Rectangle()
                .fill(Color(hex: 0xE7ECEA))
                .frame(height: 1)
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
    TransactionDetailView(
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
        onBack: {}
    )
}
