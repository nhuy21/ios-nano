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

/// Palette riêng của màn này — mirror hằng màu private trong LinkedBanksScreen.kt.
private enum LinkedBanksColor {
    static let titleInk = Color(hex: 0x111827)
    static let labelGray = Color(hex: 0x6B7280)
    static let limitBorder = Color(hex: 0xE7EAF0)
    static let limitDivider = Color(hex: 0xF0F2F5)
    static let accentGreen = Color(hex: 0x00A85E)
}

private extension String {
    /// `nil` nếu chuỗi rỗng/toàn khoảng trắng — mirror `takeIf { it.isNotBlank() }`.
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : self
    }
}

struct LinkedBanksView: View {
    let onBack: () -> Void

    @StateObject private var wallet = WalletStore.shared
    @StateObject private var authStore = AuthStore.shared
    @StateObject private var bankCache = BankCache.shared
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            topBar

            if isLoading {
                ProgressView()
                    .tint(AppColor.brand)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if wallet.bankNo == nil || wallet.accNo == nil {
                Text("Chưa có ngân hàng liên kết")
                    .font(.system(size: 14))
                    .foregroundStyle(LinkedBanksColor.labelGray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        bankCard
                        Spacer().frame(height: 6)
                        limitsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 24) }
            }
        }
        .background(Color.white)
        .task {
            await wallet.refresh()
            _ = await bankCache.get()
            isLoading = false
        }
    }

    /// Top bar nền trắng, chữ tối — mirror LinkedBanksScreen.kt (khác `DetailHeader`
    /// chuẩn của các màn Settings khác, đúng bản gốc).
    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(LinkedBanksColor.titleInk)
                    .frame(width: 40, height: 40)
                    .background(Color(hex: 0xF1F3F5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quay lại")

            Text("Ngân hàng liên kết")
                .font(AppFont.beVietnamPro(18, .bold))
                .foregroundStyle(LinkedBanksColor.titleInk)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var bankCard: some View {
        let bank = bankCache.bank(bin: wallet.bankNo)
        let name = bank.map { $0.shortName.isEmpty ? $0.name : $0.shortName } ?? "Ngân hàng liên kết"
        // `flatMap` (không phải `?.`) để `String?` + `nonEmpty` không thành `String??` —
        // tên rỗng phải rơi đúng xuống nhánh sau, mirror chuỗi `takeIf` bên Android.
        let holder = wallet.accName.flatMap { $0.nonEmpty }
            ?? authStore.userFullName.flatMap { $0.nonEmpty }
            ?? "CHỦ TÀI KHOẢN"
        return BankCard(
            bankName: name,
            accountNumber: formattedAccountNumber,
            holderName: holder,
            syncedDate: "Đồng bộ \(formattedLinkedDate)",
            brandColorHex: bank?.brandColor,
            logoUrl: bank?.logoUrl,
            bin: wallet.bankNo
        )
    }

    private var limitsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(LinkedBanksColor.accentGreen.opacity(0.12))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: "speedometer")
                            .font(.system(size: 17))
                            .foregroundStyle(LinkedBanksColor.accentGreen)
                    }
                Text("Hạn mức giao dịch")
                    .font(AppFont.beVietnamPro(16, .bold))
                    .foregroundStyle(LinkedBanksColor.titleInk)
            }
            .padding(.leading, 4)
            .padding(.bottom, 10)

            VStack(spacing: 0) {
                limitRow(label: "Xác thực PIN từ", value: pinLimitValue.vndFormatted, showDivider: true)
                limitRow(label: "Tối đa mỗi giao dịch", value: 10_000_000.vndFormatted, showDivider: true)
                limitRow(label: "Tối đa mỗi ngày", value: 20_000_000.vndFormatted, showDivider: true)
                limitRow(label: "Tối đa mỗi tháng", value: 100_000_000.vndFormatted, showDivider: false)
            }
            .padding(.horizontal, 16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(LinkedBanksColor.limitBorder, lineWidth: 1)
            }

            Spacer().frame(height: 10)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(LinkedBanksColor.accentGreen)
                Text("Giao dịch từ \(pinLimitValue.vndFormatted) trở lên cần nhập mã PIN để xác thực. Bạn có thể hạ ngưỡng này trong mục Cá nhân → Ngưỡng xác thực PIN.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(LinkedBanksColor.labelGray)
                    .lineSpacing(4)
            }
            .padding(12)
            .background(LinkedBanksColor.accentGreen.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func limitRow(label: String, value: String, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundStyle(LinkedBanksColor.labelGray)
                Spacer()
                Text(value)
                    .font(AppFont.beVietnamPro(15, .bold))
                    .foregroundStyle(LinkedBanksColor.titleInk)
            }
            .padding(.vertical, 15)

            if showDivider {
                Rectangle()
                    .fill(LinkedBanksColor.limitDivider)
                    .frame(height: 1)
            }
        }
    }

    private var pinLimitValue: Int {
        Int(wallet.limitPin ?? WalletStore.defaultLimitPin)
    }

    /// Hiện ĐẦY ĐỦ số tài khoản (không che), nhóm 4 ký tự cho dễ đọc —
    /// mirror `formatAccountNumber()` bên Android.
    private var formattedAccountNumber: String {
        let digits = (wallet.accNo ?? "").filter { $0.isLetter || $0.isNumber }
        guard !digits.isEmpty else { return "—" }
        let chunks = stride(from: 0, to: digits.count, by: 4).map { start -> String in
            let startIndex = digits.index(digits.startIndex, offsetBy: start)
            let endIndex = digits.index(startIndex, offsetBy: 4, limitedBy: digits.endIndex) ?? digits.endIndex
            return String(digits[startIndex..<endIndex])
        }
        return chunks.joined(separator: " ")
    }

    /// Không parse được / chưa có `bankLinkedAt` thì lấy ngày hôm nay —
    /// mirror `fmtLinkedDate()` bên Android (fallback `LocalDate.now()`).
    private var formattedLinkedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        formatter.locale = Locale(identifier: "vi_VN")

        guard let iso = wallet.bankLinkedAt else {
            return formatter.string(from: Date())
        }
        if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: iso)
            ?? ISO8601DateFormatter.standard.date(from: iso) {
            return formatter.string(from: date)
        }
        // Chuỗi không đúng ISO-8601: thử lấy 10 ký tự đầu dạng "yyyy-MM-dd".
        let dayOnly = DateFormatter()
        dayOnly.dateFormat = "yyyy-MM-dd"
        if let date = dayOnly.date(from: String(iso.prefix(10))) {
            return formatter.string(from: date)
        }
        return formatter.string(from: Date())
    }
}

#Preview {
    LinkedBanksView(onBack: {})
}
