//
//  BankTransferView.swift
//  nano ewallet
//
//  Mirror BankTransferScreen.kt — chọn ngân hàng + nhập STK, lookup tên chủ tài
//  khoản khi rời focus, rồi chuyển sang màn nhập số tiền (BankTransferAmountView).
//

import SwiftUI

@MainActor
struct BankTransferView: View {
    let onBack: () -> Void
    /// Người nhận đã có sẵn (từ danh bạ) — bỏ qua bước chọn bank/nhập STK, đi thẳng
    /// tới màn số tiền. `nil` = nhập tay từ đầu.
    var initialDraft: BankTransferDraft?
    let onContinue: (BankTransferDraft) -> Void
    var onOpenContacts: () -> Void = {}

    private static let bankPriority = [
        "Vietcombank", "BIDV", "VietinBank", "Agribank", "Techcombank",
        "MBBank", "ACB", "VPBank", "TPBank", "Sacombank",
    ]

    @StateObject private var bankCache = BankCache.shared
    @StateObject private var beneficiaryStore = BeneficiaryStore.shared

    @State private var selectedBin: String?
    @State private var accountNumber = ""
    @State private var accType = 0 // 0: STK, 1: Thẻ
    @State private var holderName = ""
    @State private var isLookingUp = false
    @State private var lookupError: String?
    @State private var lastLookedUp: (bin: String, account: String, accType: Int)?
    @State private var showAllBanks = false

    @FocusState private var isAccountFocused: Bool

    private var sortedBanks: [Bank] {
        bankCache.banks.sorted { a, b in
            let ia = Self.bankPriority.firstIndex(of: a.shortName) ?? Int.max
            let ib = Self.bankPriority.firstIndex(of: b.shortName) ?? Int.max
            return ia < ib
        }
    }

    private var selectedBank: Bank? {
        bankCache.banks.first { $0.bin == selectedBin }
    }

    private var recentBankContacts: [Beneficiary] {
        beneficiaryStore.beneficiaries.filter { $0.type == .bankAccount }
    }

    private var canContinue: Bool {
        selectedBin != nil && !accountNumber.isEmpty && !holderName.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    bankPickerSection
                    accountSection
                    if !recentBankContacts.isEmpty {
                        recentSection
                    }
                }
                .padding(16)
            }
            continueBar
        }
        .background(Color(hex: 0xF7F8FA))
        .task {
            _ = await bankCache.get()
            await beneficiaryStore.refresh()
        }
        .sheet(isPresented: $showAllBanks) {
            BankPickerSheet(banks: sortedBanks, selectedBin: $selectedBin, onDismiss: { showAllBanks = false })
        }
        .onAppear {
            if let initialDraft {
                selectedBin = initialDraft.bin
                accountNumber = initialDraft.accNo
                accType = initialDraft.accType
                holderName = initialDraft.holderName
            }
        }
        .onChange(of: selectedBin) { _, _ in runLookupIfNeeded() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("CHUYỂN KHOẢN NGÂN HÀNG")
                .font(AppFont.beVietnamPro(15, .bold))
                .foregroundStyle(.white)
                .tracking(1)

            Spacer()

            Button(action: onOpenContacts) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Danh bạ")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                colors: [Color(hex: 0x2ECB6E), Color(hex: 0x00A24A)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
    }

    // MARK: - Chọn ngân hàng

    private var bankPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                FieldLabel(text: "Ngân hàng")
                    .padding(.bottom, 0)
                Spacer()
                Button("Xem tất cả") { showAllBanks = true }
                    .buttonStyle(.plain)
                    .font(AppFont.beVietnamPro(13, .semibold))
                    .foregroundStyle(AppColor.brand)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(sortedBanks.prefix(10)) { bank in
                        bankChip(bank)
                    }
                }
            }
        }
    }

    private func bankChip(_ bank: Bank) -> some View {
        let isSelected = bank.bin == selectedBin
        return Button {
            selectedBin = bank.bin
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? AppColor.brand : Color.white)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Text(bank.shortName.prefix(4))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(isSelected ? .white : AppColor.payInk)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? Color.clear : AppColor.payInputBorder, lineWidth: 1)
                    }
                Text(bank.shortName)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColor.payInk)
                    .lineLimit(1)
            }
            .frame(width: 64)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Số tài khoản

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                accTypeToggle(title: "Số tài khoản", index: 0)
                accTypeToggle(title: "Số thẻ", index: 1)
            }
            .padding(3)
            .background(Color(hex: 0xF1F3F5))
            .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: accType == 0 ? "Số tài khoản" : "Số thẻ")
                AppTextField(
                    text: $accountNumber,
                    placeholder: "Nhập số tài khoản",
                    keyboardType: .numberPad,
                    submitLabel: .done,
                    digitsOnly: true
                )
                .focused($isAccountFocused)
                .numericKeyboardToolbar(label: "Xong") { isAccountFocused = false }
                .onChange(of: isAccountFocused) { wasFocused, isFocused in
                    if wasFocused && !isFocused { runLookupIfNeeded() }
                }
            }

            if isLookingUp {
                HStack(spacing: 8) {
                    ProgressView().tint(AppColor.brand)
                    Text("Đang tra cứu tên chủ tài khoản...")
                        .font(AppFont.beVietnamPro(13))
                        .foregroundStyle(AppColor.payMuted)
                }
            } else if let lookupError {
                FieldError(message: lookupError, alignment: .leading)
            } else if !holderName.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tên chủ tài khoản")
                        .font(AppFont.beVietnamPro(12))
                        .foregroundStyle(AppColor.payMuted)
                    Text(holderName)
                        .font(AppFont.beVietnamPro(15, .semibold))
                        .foregroundStyle(AppColor.payInk)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColor.brandSoft)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func accTypeToggle(title: String, index: Int) -> some View {
        let isSelected = accType == index
        return Button {
            accType = index
            holderName = ""
            lastLookedUp = nil
            runLookupIfNeeded()
        } label: {
            Text(title)
                .font(AppFont.beVietnamPro(13, .semibold))
                .foregroundStyle(isSelected ? .white : AppColor.payMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? AppColor.brand : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Người nhận gần đây

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel(text: "Người nhận gần đây").padding(.bottom, 0)
            VStack(spacing: 0) {
                ForEach(recentBankContacts.prefix(5)) { contact in
                    Button {
                        pick(contact)
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(AppColor.brandSoft)
                                .frame(width: 36, height: 36)
                                .overlay {
                                    Text(String(contact.displayName.prefix(1)).uppercased())
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(AppColor.brand)
                                }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.displayName)
                                    .font(AppFont.beVietnamPro(14, .semibold))
                                    .foregroundStyle(AppColor.payInk)
                                Text(contact.accNo ?? "")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppColor.payMuted)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func pick(_ contact: Beneficiary) {
        selectedBin = contact.bankNo
        accountNumber = contact.accNo ?? ""
        holderName = contact.accName ?? contact.displayName
        lastLookedUp = (contact.bankNo ?? "", contact.accNo ?? "", accType)
    }

    // MARK: - Continue

    private var continueBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(AppColor.line).frame(height: 1)
            PrimaryButton(title: "Tiếp tục", isEnabled: canContinue) {
                guard let bank = selectedBank else { return }
                onContinue(
                    BankTransferDraft(
                        bin: bank.bin, bankName: bank.shortName,
                        accNo: accountNumber, accType: accType, holderName: holderName
                    )
                )
            }
            .padding(16)
        }
        .background(Color.white)
    }

    // MARK: - Lookup

    private func runLookupIfNeeded() {
        guard let bin = selectedBin, accountNumber.count >= 4 else { return }
        let key = (bin, accountNumber, accType)
        if let lastLookedUp, lastLookedUp == key { return }
        lastLookedUp = key
        lookupError = nil
        Task {
            isLookingUp = true
            defer { isLookingUp = false }
            do {
                holderName = try await BankService.lookupAccount(bin: bin, accountNumber: accountNumber)
            } catch let error as APIError {
                holderName = ""
                lookupError = error.message
            } catch {
                holderName = ""
                lookupError = "Không tra cứu được tên chủ tài khoản"
            }
        }
    }
}

/// Sheet "Xem tất cả" — danh sách đầy đủ, tìm kiếm không dấu (mirror BankTransferScreen.kt).
private struct BankPickerSheet: View {
    let banks: [Bank]
    @Binding var selectedBin: String?
    let onDismiss: () -> Void

    @State private var query = ""

    private var filtered: [Bank] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return banks }
        let needle = trimmed.noAccentLowercased
        return banks.filter {
            $0.shortName.noAccentLowercased.contains(needle) || $0.name.noAccentLowercased.contains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(AppColor.line)
                .frame(width: 40, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 12)

            Text("Chọn ngân hàng")
                .font(AppFont.beVietnamPro(16, .bold))
                .foregroundStyle(AppColor.payInk)
                .padding(.bottom, 12)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(AppColor.payMuted)
                TextField("Tìm ngân hàng...", text: $query)
                    .font(.system(size: 14))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(hex: 0xF1F3F5))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { bank in
                        Button {
                            selectedBin = bank.bin
                            onDismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Text(bank.shortName)
                                    .font(AppFont.beVietnamPro(14, .semibold))
                                    .foregroundStyle(AppColor.payInk)
                                Spacer()
                                Text(bank.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppColor.payMuted)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        Rectangle().fill(AppColor.line).frame(height: 1)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .presentationDetents([.large])
    }
}

private extension String {
    /// Bỏ dấu tiếng Việt + hạ chữ thường để tìm kiếm không phân biệt dấu/hoa-thường.
    var noAccentLowercased: String {
        folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
            .lowercased()
    }
}

#Preview {
    BankTransferView(onBack: {}, onContinue: { _ in })
}
