//
//  AddContactSheet.swift
//  nano ewallet
//
//  Mirror AddContactSheet.kt — thêm contact ngân hàng (BANK_ACCOUNT) hoặc ví (WALLET).
//  Loại do MÀN GỌI quyết định (`type`), không có nút đổi trong form: người dùng luôn vào
//  đây từ một tab/luồng đã xác định loại rồi, hỏi lại là thừa một bước.
//

import SwiftUI

struct AddContactSheet: View {
    /// Loại mở form lần đầu. Mở từ Trang chủ thì chỉ là gợi ý — người dùng đổi ngay trong
    /// form; mở từ một luồng chuyển tiền thì `isTypeLocked` khoá lại.
    let initialType: BeneficiaryType
    /// Vào từ một luồng chuyển tiền cụ thể -> loại do luồng quyết định, ẩn phần chọn.
    /// Chọn nhầm loại ở đây sẽ đưa người dùng vào màn chuyển tiền sai.
    var isTypeLocked: Bool = false
    let onSaved: () -> Void
    let onCancel: () -> Void

    /// Loại người nhận — quyết định toàn bộ form (ô nhập, cách tra cứu tên).
    @State private var type: BeneficiaryType

    init(
        initialType: BeneficiaryType,
        isTypeLocked: Bool = false,
        onSaved: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialType = initialType
        self.isTypeLocked = isTypeLocked
        self.onSaved = onSaved
        self.onCancel = onCancel
        _type = State(initialValue: initialType)
    }

    /// Số tài khoản ngân hàng (nhánh `.bankAccount`) hoặc số ví (nhánh `.wallet`).
    @State private var accountNumber = ""
    @State private var nickname = ""
    @State private var selectedBank: Bank?
    @State private var showBankSheet = false

    /// Quan sát THẲNG cache thay vì copy vào `@State` riêng: `BankCache.get()` trả về mảng
    /// RỖNG ngay nếu đang có lượt tải khác chạy dở (`isLoading`), mà `.task` chỉ chạy một
    /// lần — copy trúng lúc đó là danh sách rỗng vĩnh viễn.
    @StateObject private var bankCache = BankCache.shared
    private var banks: [Bank] { bankCache.banks }

    @State private var holderName: String?
    @State private var lookupError: String?
    @State private var isLookingUp = false
    @State private var lookupTask: Task<Void, Never>?

    @State private var isSaving = false
    @State private var saveError: String?

    @FocusState private var isAccountFocused: Bool

    /// `BankPickerSheet` nhận `Binding<String?>` theo BIN, còn form này giữ cả `Bank` để
    /// hiện logo/tên — cầu nối hai chiều, đồng thời tra lại tên chủ TK ngay khi đổi bank.
    private var bankBinBinding: Binding<String?> {
        Binding(
            get: { selectedBank?.bin },
            set: { newBin in
                guard let newBin, newBin != selectedBank?.bin else { return }
                selectedBank = banks.first { $0.bin == newBin }
                triggerLookup()
            }
        )
    }

    private var canSave: Bool {
        guard !accountNumber.isEmpty, !(holderName ?? "").isEmpty, !isSaving else { return false }
        // Ví không có ngân hàng để chọn nên bỏ điều kiện đó, còn lại giống hệt.
        return type == .wallet || selectedBank != nil
    }

    /// Hai ô chọn loại — đổi loại là xoá sạch dữ liệu đã nhập: số ví và số tài khoản ngân
    /// hàng không dùng chung định dạng, giữ lại sẽ tra cứu ra kết quả vô nghĩa hoặc lưu nhầm.
    private var typeSelector: some View {
        HStack(spacing: 10) {
            typeOption(.wallet, title: "Ví nano", systemImage: "wallet.pass")
            typeOption(.bankAccount, title: "Ngân hàng", systemImage: "building.columns")
        }
    }

    private func typeOption(
        _ value: BeneficiaryType, title: String, systemImage: String
    ) -> some View {
        let isActive = type == value
        return Button {
            guard type != value else { return }
            type = value
            resetEnteredData()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 15))
                Text(title)
                    .font(AppFont.beVietnamPro(14, .semibold))
            }
            .foregroundStyle(isActive ? AppColor.brand : AppColor.payMuted)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(isActive ? AppColor.brandSoft : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isActive ? AppColor.brand : AppColor.payInputBorder,
                        lineWidth: isActive ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private func resetEnteredData() {
        lookupTask?.cancel()
        accountNumber = ""
        selectedBank = nil
        holderName = nil
        lookupError = nil
        isLookingUp = false
        saveError = nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !isTypeLocked {
                        fieldBlock(label: "Loại người nhận") { typeSelector }
                    }

                    // Ngân hàng đứng TRƯỚC số tài khoản: tra cứu tên chủ TK cần cả hai, mà
                    // chọn ngân hàng sau khi gõ xong số thì phải quay lại sửa — mirror thứ tự
                    // ở BankTransferView. Ví nội bộ không có bước này.
                    if type == .bankAccount {
                        fieldBlock(label: "Ngân hàng") {
                            bankSelectButton
                        }
                    }

                    fieldBlock(label: type == .wallet ? "Số ví" : "Số tài khoản") {
                        TextField(
                            "", text: $accountNumber,
                            prompt: .appPlaceholder(
                                type == .wallet ? "Nhập số ví..." : "Nhập số tài khoản..."
                            )
                        )
                        .font(AppFont.beVietnamPro(18, .medium))
                        .foregroundStyle(AppColor.payInk)
                        .tint(AppColor.brand)
                        .keyboardType(.numberPad)
                        .submitLabel(.done)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 56)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(AppColor.payInputBorder, lineWidth: 1)
                        }
                        .focused($isAccountFocused)
                        .onSubmit { triggerLookup() }
                        // Chỉ tra cứu khi RỜI focus (bấm ra ngoài/chuyển ô khác) hoặc bấm
                        // Done — không gọi API mỗi lần gõ ký tự, mirror BankTransferView.
                        .onChangeCompat(of: isAccountFocused) { wasFocused, isFocused in
                            if wasFocused && !isFocused { triggerLookup() }
                        }
                        .onChangeCompat(of: accountNumber) { _, newValue in
                            let filtered = newValue.filter(\.isNumber)
                            if filtered != newValue {
                                accountNumber = filtered
                            } else if !filtered.isEmpty {
                                holderName = nil; lookupError = nil
                            }
                        }
                    }

                    fieldBlock(label: type == .wallet ? "Tên chủ ví" : "Tên chủ tài khoản") {
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
        // `fullScreenCover` chứ KHÔNG phải `.sheet`: màn này bản thân đã là một sheet
        // (mở từ ContactsView), mà iOS không hiện sheet lồng trong sheet — bấm nút chọn
        // ngân hàng sẽ không thấy gì.
        //
        // `BankPickerSheet` vốn dựng cho `.sheet` (chỉ có thanh kéo, không có nút đóng) nên
        // phải tự thêm nút Đóng, không thì kẹt trong đó không thoát ra được.
        .fullScreenCover(isPresented: $showBankSheet) {
            VStack(spacing: 0) {
                BankPickerSheet(
                    banks: banks,
                    selectedBin: bankBinBinding,
                    onDismiss: { showBankSheet = false }
                )

                Button("Đóng") { showBankSheet = false }
                    .buttonStyle(.plain)
                    .font(AppFont.beVietnamPro(15, .semibold))
                    .foregroundStyle(AppColor.brand)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(Rectangle())
            }
            .background(Color.white)
        }
        .task {
            // Nhánh ví không chọn ngân hàng nên khỏi tải danh sách. Kết quả tự về qua
            // `@Published banks` của cache, không cần gán lại vào state.
            guard type == .bankAccount else { return }
            _ = await bankCache.get()
        }
    }

    private var header: some View {
        HStack {
            Text(type == .wallet ? "Thêm người nhận ví" : "Thêm người nhận ngân hàng")
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
        if type == .wallet { return "Nhập số ví để tra cứu" }
        if selectedBank == nil { return "Chọn ngân hàng bên dưới" }
        return "Nhập số tài khoản để tra cứu"
    }

    /// Ô bấm mở `BankPickerSheet` (sheet dùng chung với màn chuyển khoản) thay cho lưới
    /// logo 4 cột trước đây: danh sách ngân hàng dài, nhét cả lưới vào form làm ô nhập số
    /// tài khoản bị đẩy khuất tận đáy.
    private var bankSelectButton: some View {
        Button {
            isAccountFocused = false
            showBankSheet = true
        } label: {
            HStack(spacing: 12) {
                if let bank = selectedBank {
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
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                }

                Text(selectedBank?.shortName ?? "Chọn ngân hàng")
                    .font(AppFont.beVietnamPro(16, .medium))
                    .foregroundStyle(selectedBank == nil ? AppColor.payPlaceholder : AppColor.payInk)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColor.payMuted)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AppColor.payInputBorder, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func bankFallback(_ bank: Bank) -> some View {
        let color = bank.brandColor.flatMap { Color(hexString: $0) } ?? AppColor.brand
        return Circle()
            .fill(color)
            .overlay {
                Text(String(bank.shortName.prefix(4)))
                    .font(AppFont.beVietnamPro(9, .bold))
                    .foregroundStyle(.white)
            }
    }

    private func triggerLookup() {
        lookupTask?.cancel()
        holderName = nil
        lookupError = nil
        guard accountNumber.count >= 6 else { return }
        // Ví tra qua wallet/verify-beneficiary (chỉ cần số ví), ngân hàng vẫn cần bin đã chọn.
        var bin: String?
        if type == .bankAccount {
            guard let selected = selectedBank?.bin else { return }
            bin = selected
        }
        let username = accountNumber
        lookupTask = Task {
            isLookingUp = true
            do {
                let name: String
                if let bin {
                    name = try await BankService.lookupAccount(bin: bin, accountNumber: username)
                } else {
                    name = try await TransferService.verifyBeneficiary(
                        VerifyBeneficiaryRequest(benUsername: username)
                    )
                }
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
        guard let holderName else { return }
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespaces)
        // Hai loại gửi hai bộ field khác nhau: BE bật forbidNonWhitelisted nên gửi thừa
        // field của loại kia sẽ bị từ chối.
        let request: CreateBeneficiaryRequest
        switch type {
        case .bankAccount:
            guard let bank = selectedBank else { return }
            request = CreateBeneficiaryRequest(
                type: .bankAccount,
                bankNo: bank.bin,
                accNo: accountNumber,
                accName: holderName,
                nickname: trimmedNickname.isEmpty ? nil : trimmedNickname
            )
        case .wallet:
            // Thứ tự tham số phải khớp thứ tự khai báo trong `CreateBeneficiaryRequest`
            // (accName đứng trước benUsername) — memberwise init không cho đảo.
            request = CreateBeneficiaryRequest(
                type: .wallet,
                accName: holderName,
                benUsername: accountNumber,
                nickname: trimmedNickname.isEmpty ? nil : trimmedNickname
            )
        }
        isSaving = true
        saveError = nil
        Task {
            do {
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

#Preview("Chọn được loại") {
    AddContactSheet(initialType: .wallet, onSaved: {}, onCancel: {})
}

#Preview("Khoá loại (vào từ luồng chuyển tiền)") {
    AddContactSheet(initialType: .bankAccount, isTypeLocked: true, onSaved: {}, onCancel: {})
}
