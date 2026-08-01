//
//  LinkedBanksView.swift
//  nano ewallet
//
//  Mirror LinkedBanksScreen.kt — đọc từ WalletStore (đã cache), map bin -> tên/logo
//  qua BankCache. Hạn mức giao dịch/ngày/tháng là hằng số tĩnh bên Android (không có
//  API riêng), giữ nguyên.
//

import SwiftUI
import Combine

struct LinkedBanksView: View {
    let onBack: () -> Void

    @StateObject private var wallet = WalletStore.shared
    @StateObject private var authStore = AuthStore.shared
    @StateObject private var bankCache = BankCache.shared
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(title: "Ngân hàng liên kết", onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isLoading {
                        ProgressView()
                            .tint(AppColor.brand)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if wallet.bankNo == nil || wallet.accNo == nil {
                        Text("Chưa có ngân hàng liên kết")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColor.payMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        bankCard
                        limitsSection
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 24) }
        }
        .background(Color(hex: 0xF7F8FA))
        .task {
            await wallet.refresh()
            _ = await bankCache.get()
            isLoading = false
        }
    }

    private var bankCard: some View {
        let bank = bankCache.bank(bin: wallet.bankNo)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let logoUrl = bank?.logoUrl, let url = URL(string: logoUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Color(hex: 0xF5F7F6)
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppColor.brandSoft)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "building.columns.fill")
                                .foregroundStyle(AppColor.brand)
                        }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(bank?.shortName ?? "Ngân hàng liên kết")
                        .font(AppFont.beVietnamPro(16, .bold))
                        .foregroundStyle(AppColor.payInk)
                    if let linkedAt = formattedLinkedDate {
                        Text("Đồng bộ \(linkedAt)")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColor.payMuted)
                    }
                }

                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text(formattedAccountNumber)
                    .font(AppFont.beVietnamPro(18, .semibold))
                    .foregroundStyle(AppColor.payInk)
                Text(authStore.userFullName?.uppercased() ?? "CHỦ TÀI KHOẢN")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColor.payMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color(hex: 0x784628).opacity(0x14 / 255.0), radius: 8, x: 0, y: 3)
    }

    private var limitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(AppColor.brandSoft)
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "speedometer")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColor.brand)
                    }
                Text("Hạn mức giao dịch")
                    .font(AppFont.beVietnamPro(15, .bold))
                    .foregroundStyle(AppColor.payInk)
            }

            VStack(spacing: 0) {
                limitRow(label: "Xác thực PIN từ", value: pinLimitValue.vndFormatted)
                divider
                limitRow(label: "Tối đa mỗi giao dịch", value: "10.000.000đ")
                divider
                limitRow(label: "Tối đa mỗi ngày", value: "20.000.000đ")
                divider
                limitRow(label: "Tối đa mỗi tháng", value: "100.000.000đ")
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AppColor.line, lineWidth: 1)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColor.brand)
                Text("Giao dịch từ \(pinLimitValue.vndFormatted) trở lên cần nhập mã PIN để xác thực. Bạn có thể hạ ngưỡng này trong mục Cá nhân → Ngưỡng xác thực PIN.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.payMuted)
            }
            .padding(12)
            .background(AppColor.brand.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var divider: some View {
        Rectangle().fill(AppColor.line).frame(height: 1).padding(.leading, 16)
    }

    private func limitRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(AppColor.payMuted)
            Spacer()
            Text(value)
                .font(AppFont.beVietnamPro(14, .semibold))
                .foregroundStyle(AppColor.payInk)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }

    private var pinLimitValue: Int {
        Int(wallet.limitPin ?? WalletStore.defaultLimitPin)
    }

    private var formattedAccountNumber: String {
        guard let accNo = wallet.accNo else { return "—" }
        // Nhóm 4 ký tự cách nhau, không che số — mirror BankCard bên Android.
        let chunks = stride(from: 0, to: accNo.count, by: 4).map { start -> String in
            let startIndex = accNo.index(accNo.startIndex, offsetBy: start)
            let endIndex = accNo.index(startIndex, offsetBy: 4, limitedBy: accNo.endIndex) ?? accNo.endIndex
            return String(accNo[startIndex..<endIndex])
        }
        return chunks.joined(separator: " ")
    }

    private var formattedLinkedDate: String? {
        guard let iso = wallet.bankLinkedAt,
              let date = ISO8601DateFormatter.withFractionalSeconds.date(from: iso)
                ?? ISO8601DateFormatter.standard.date(from: iso) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }
}

#Preview {
    LinkedBanksView(onBack: {})
}
