//
//  AddContactSheet.swift
//  nano ewallet
//
//  Mirror AddContactSheet.kt — CHỈ hỗ trợ thêm contact loại Ngân hàng (BANK_ACCOUNT),
//  đúng bản gốc Android (createWallet có sẵn ở service nhưng không có UI gọi).
//

import SwiftUI

struct AddContactSheet: View {
    let onSaved: () -> Void
    let onCancel: () -> Void

    @State private var accountNumber = ""
    @State private var nickname = ""
    @State private var selectedBank: Bank?
    @State private var bankSearch = ""
    @State private var banks: [Bank] = []
    @State private var isLoadingBanks = true

    @State private var holderName: String?
    @State private var lookupError: String?
    @State private var isLookingUp = false
    @State private var lookupTask: Task<Void, Never>?

    @State private var isSaving = false
    @State private var saveError: String?

    private var filteredBanks: [Bank] {
        let trimmed = bankSearch.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return banks }
        return banks.filter {
            $0.shortName.localizedCaseInsensitiveContains(trimmed)
                || $0.name.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var canSave: Bool {
        selectedBank != nil && !accountNumber.isEmpty && !(holderName ?? "").isEmpty && !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    fieldBlock(label: "Số tài khoản") {
                        AppTextField(
                            text: $accountNumber,
                            placeholder: "Nhập số tài khoản...",
                            keyboardType: .numberPad,
                            digitsOnly: true
                        )
                        .onChange(of: accountNumber) { _, _ in triggerLookup() }
                    }

                    fieldBlock(label: "Tên chủ tài khoản") {
                        Text(holderNameDisplay)
                            .font(AppFont.beVietnamPro(15, .semibold))
                            .foregroundStyle(holderName != nil ? AppColor.payInk : AppColor.payMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 56)
                            .background(Color(hex: 0xF6F7F9))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    fieldBlock(label: "Tên gợi nhớ (tuỳ chọn)") {
                        AppTextField(text: $nickname, placeholder: "Vd: Mẹ, Tiền nhà...", maxLength: 100)
                    }

                    fieldBlock(label: "Ngân hàng") {
                        bankPicker
                    }

                    if let saveError {
                        FieldError(message: saveError)
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 24) }

            PrimaryButton(
                title: "LƯU VÀO DANH BẠ",
                loadingTitle: "Đang lưu...",
                isLoading: isSaving,
                isEnabled: canSave,
                action: save
            )
            .padding(20)
        }
        .background(Color(hex: 0xF7F8FA))
        .task {
            banks = await BankCache.shared.get()
            isLoadingBanks = false
        }
    }

    private var header: some View {
        HStack {
            Text("Thêm người nhận")
                .font(AppFont.beVietnamPro(18, .bold))
                .foregroundStyle(AppColor.payInk)
            Spacer()
            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColor.payInk)
                    .frame(width: 36, height: 36)
                    .background(Color(hex: 0xF6F7F9))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Đóng")
        }
        .padding(20)
    }

    @ViewBuilder
    private func fieldBlock<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(AppFont.beVietnamPro(13, .semibold))
                .foregroundStyle(AppColor.payInk)
            content()
        }
    }

    private var holderNameDisplay: String {
        if isLookingUp { return "Đang tra cứu..." }
        if let holderName { return holderName.uppercased() }
        if let lookupError { return lookupError }
        if selectedBank == nil { return "Chọn ngân hàng bên dưới" }
        return "Nhập số tài khoản để tra cứu"
    }

    private var bankPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColor.payMuted)
                TextField("Tìm ngân hàng...", text: $bankSearch)
                    .font(.system(size: 14))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AppColor.payInputBorder, lineWidth: 1)
            }

            if isLoadingBanks {
                Text("Đang tải danh sách ngân hàng...")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColor.payMuted)
                    .padding(.top, 8)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    ForEach(filteredBanks) { bank in
                        bankCell(bank)
                    }
                }
            }
        }
    }

    private func bankCell(_ bank: Bank) -> some View {
        let isSelected = selectedBank?.id == bank.id
        return Button {
            selectedBank = bank
            triggerLookup()
        } label: {
            VStack(spacing: 4) {
                Group {
                    if let logoUrl = bank.logoUrl, let url = URL(string: logoUrl) {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fit)
                        } placeholder: {
                            bankFallback(bank)
                        }
                    } else {
                        bankFallback(bank)
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                .overlay {
                    Circle().strokeBorder(isSelected ? AppColor.brand : Color.clear, lineWidth: 2)
                }

                Text(bank.shortName)
                    .font(.system(size: 10))
                    .foregroundStyle(AppColor.payInk)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private func bankFallback(_ bank: Bank) -> some View {
        let color = bank.brandColor.flatMap { Color(hexString: $0) } ?? AppColor.brand
        return Circle()
            .fill(color)
            .overlay {
                Text(String(bank.shortName.prefix(4)))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
    }

    private func triggerLookup() {
        lookupTask?.cancel()
        holderName = nil
        lookupError = nil
        guard let bin = selectedBank?.bin, accountNumber.count >= 6 else { return }
        lookupTask = Task {
            isLookingUp = true
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            do {
                let name = try await BankService.lookupAccount(bin: bin, accountNumber: accountNumber)
                guard !Task.isCancelled else { return }
                holderName = name
            } catch {
                guard !Task.isCancelled else { return }
                lookupError = (error as? APIError)?.message ?? "Không tra cứu được, vui lòng thử lại"
            }
            isLookingUp = false
        }
    }

    private func save() {
        guard let bank = selectedBank, let holderName else { return }
        isSaving = true
        saveError = nil
        Task {
            do {
                let request = CreateBeneficiaryRequest(
                    type: .bankAccount,
                    bankNo: bank.bin,
                    accNo: accountNumber,
                    accName: holderName,
                    nickname: nickname.trimmingCharacters(in: .whitespaces).isEmpty
                        ? nil : nickname.trimmingCharacters(in: .whitespaces)
                )
                _ = try await BeneficiaryStore.shared.create(request)
                isSaving = false
                onSaved()
            } catch {
                isSaving = false
                saveError = (error as? APIError)?.message ?? "Không lưu được, vui lòng thử lại"
            }
        }
    }
}

#Preview {
    AddContactSheet(onSaved: {}, onCancel: {})
}
