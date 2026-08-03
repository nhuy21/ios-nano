//
//  KycReviewView.swift
//  nano ewallet
//
//  Mirror KycReviewScreen.kt — bổ sung địa chỉ tạm trú + 4 lựa chọn phân loại, chọn tài
//  khoản ngân hàng nhận tiền rồi nộp hồ sơ eKYC.
//
//  KHÔNG hiện lại thông tin đọc từ chip: người dùng vừa xem và xác nhận ngay trong SDK,
//  bày lại lần nữa chỉ làm màn dài thêm mà không sửa được gì.
//
//  Vào màn là đối soát C06 NGAY (passive authentication chip NFC): gửi dữ liệu chip thô
//  lên BE xác thực chữ ký số CSCA. Trong lúc chờ che overlay chặn thao tác; thẻ không
//  hợp lệ thì bắt quét lại — để người dùng điền hết form rồi mới báo là phí công họ.
//
//  Nộp xong, Bảo Kim soi từng trường: còn trường sai/thiếu thì sang màn sửa, sửa xong
//  vẫn lỗi thì lặp lại, sạch lỗi mới đi tiếp.
//

import SwiftUI

struct KycReviewView: View {

    let onBack: () -> Void
    /// Hồ sơ đã sạch lỗi — bước tiếp theo là ký thoả thuận mở ví.
    let onSubmitted: () -> Void

    private static let popularBanks = ["Vietcombank", "MBBank", "VietinBank", "BIDV", "Techcombank", "Agribank"]
    private static let bankColumns = 3

    @StateObject private var pending = PendingKyc.shared
    @StateObject private var bankCache = BankCache.shared

    // Bổ sung
    @State private var temporaryLocation = ""
    @State private var business: String?
    @State private var position: String?
    @State private var purposeOfUsing: String?
    @State private var businessAreaId: String?

    // Ngân hàng
    @State private var selectedBank: Bank?
    @State private var showAllBanks = false
    @State private var searchQuery = ""
    @State private var accNo = ""
    @State private var accName = ""
    @State private var isLookingUp = false
    @State private var lookupError: String?
    /// Cặp (bin, số TK) vừa tra — rời focus nhiều lần mà không sửa gì thì khỏi gọi lại.
    @State private var lastLookedUp: String?
    @FocusState private var isAccountFocused: Bool

    // Nộp hồ sơ
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var fieldsToFix: [BkField] = []

    // Đối soát C06
    @State private var isVerifyingC06 = true
    @State private var c06Error: String?

    private var canSubmit: Bool {
        selectedBank != nil && !accNo.isEmpty && !accName.isEmpty
            && !temporaryLocation.trimmingCharacters(in: .whitespaces).isEmpty
            && business != nil && position != nil
            && purposeOfUsing != nil && businessAreaId != nil
            && !isSubmitting
    }

    private var visibleBanks: [Bank] {
        let all = bankCache.banks
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            let needle = query.lowercased()
            return all.filter {
                $0.name.lowercased().contains(needle) || $0.shortName.lowercased().contains(needle)
            }
        }
        if showAllBanks { return all }
        let popular = Self.popularBanks.compactMap { name in all.first { $0.shortName == name } }
        return popular.isEmpty ? Array(all.prefix(6)) : popular
    }

    var body: some View {
        ZStack {
            content

            if isVerifyingC06 {
                verifyingOverlay
            }
        }
        .background(Color.white)
        .task { await verifyC06() }
        .task { _ = await bankCache.get() }
        .alert(
            "Xác thực CCCD",
            isPresented: Binding(get: { c06Error != nil }, set: { if !$0 { c06Error = nil } })
        ) {
            Button("Quét lại") { c06Error = nil; onBack() }
        } message: {
            Text(c06Error ?? "")
        }
        .fullScreenCover(isPresented: Binding(
            get: { !fieldsToFix.isEmpty },
            set: { if !$0 { fieldsToFix = [] } }
        )) {
            FixEkycFieldsView(
                fields: fieldsToFix,
                onBack: { fieldsToFix = [] },
                onResult: { result in
                    let stillFailing = result.fieldsNeedingFix
                    if stillFailing.isEmpty {
                        fieldsToFix = []
                        onSubmitted()
                    } else {
                        fieldsToFix = stillFailing
                    }
                }
            )
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Chặn thoát khi đang đối soát C06: rời màn giữa lúc chờ thì hồ sơ đã quét
            // xong bị bỏ, người dùng phải quét lại CCCD từ đầu.
            BackHeader(action: { if !isVerifyingC06 { onBack() } })
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Bổ sung thông tin")
                        .font(AppFont.beVietnamPro(24, .heavy))
                        .foregroundStyle(AppColor.payInk)

                    Text("Hoàn thiện hồ sơ và liên kết tài khoản ngân hàng để mở ví")
                        .font(AppFont.beVietnamPro(14))
                        .foregroundStyle(AppColor.payMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)

                    additionalSection
                        .padding(.top, 24)

                    Text("Tài khoản ngân hàng")
                        .font(AppFont.beVietnamPro(16, .bold))
                        .foregroundStyle(AppColor.payInk)
                        .padding(.top, 20)
                        .padding(.bottom, 10)

                    bankSection

                    if let submitError {
                        Text(submitError)
                            .font(AppFont.beVietnamPro(13))
                            .foregroundStyle(AppColor.error)
                            .padding(.top, 16)
                    }

                    submitButton
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - Bổ sung

    private var additionalSection: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Địa chỉ tạm trú")
                    .font(AppFont.beVietnamPro(12, .semibold))
                    .foregroundStyle(AppColor.payInk)

                TextField("Nhập địa chỉ tạm trú", text: $temporaryLocation)
                    .font(AppFont.beVietnamPro(14))
                    .foregroundStyle(AppColor.payInk)
                    .tint(AppColor.brand)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    // Cao đúng bằng ô chọn bên dưới: ô kia có mũi tên 24pt nên phải kê
                    // chiều cao tối thiểu, không thì hai ô so le nhau.
                    .frame(minHeight: 48)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AppColor.payInputBorder, lineWidth: 1)
                    }
            }
            .padding(.vertical, 6)

            optionField("Nghề nghiệp", KycOptions.business, $business)
            optionField("Chức vụ", KycOptions.position, $position)
            optionField("Mục đích sử dụng", KycOptions.purposeOfUsing, $purposeOfUsing)
            optionField("Ngành nghề, lĩnh vực kinh doanh", KycOptions.businessArea, $businessAreaId)
        }
    }

    private func optionField(
        _ label: String, _ options: [KycOption], _ selection: Binding<String?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppFont.beVietnamPro(12, .semibold))
                .foregroundStyle(AppColor.payInk)
            KycOptionDropdown(title: label, options: options, selectedCode: selection)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Ngân hàng

    private var bankSection: some View {
        sectionCard {
            if bankCache.banks.isEmpty {
                Text("Đang tải danh sách ngân hàng...")
                    .font(AppFont.beVietnamPro(13))
                    .foregroundStyle(AppColor.payMuted)
            } else {
                if showAllBanks || !searchQuery.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(AppColor.payMuted)
                        TextField("Tìm ngân hàng theo tên", text: $searchQuery)
                            .font(AppFont.beVietnamPro(14))
                            .tint(AppColor.brand)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AppColor.payInputBorder, lineWidth: 1)
                    }
                    .padding(.bottom, 12)
                }

                bankGrid

                if visibleBanks.isEmpty {
                    Text("Không tìm thấy ngân hàng phù hợp")
                        .font(AppFont.beVietnamPro(13))
                        .foregroundStyle(AppColor.payMuted)
                }

                if searchQuery.isEmpty {
                    Button { showAllBanks.toggle() } label: {
                        Text(showAllBanks ? "Thu gọn" : "Xem tất cả ngân hàng")
                            .font(AppFont.beVietnamPro(13, .semibold))
                            .foregroundStyle(AppColor.brand)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }

            accountField
                .padding(.top, 8)

            if isLookingUp {
                HStack(spacing: 8) {
                    ProgressView().progressViewStyle(.circular).tint(AppColor.brand).scaleEffect(0.7)
                    Text("Đang tra cứu...")
                        .font(AppFont.beVietnamPro(12))
                        .foregroundStyle(AppColor.payMuted)
                }
                .padding(.top, 10)
            }

            if let lookupError {
                Text(lookupError)
                    .font(AppFont.beVietnamPro(13, .semibold))
                    .foregroundStyle(AppColor.error)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColor.errorSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.top, 10)
            }

            if !accName.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppColor.brand)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Chủ tài khoản")
                            .font(AppFont.beVietnamPro(11))
                            .foregroundStyle(AppColor.payMuted)
                        Text(accName)
                            .font(AppFont.beVietnamPro(14, .bold))
                            .foregroundStyle(AppColor.payInk)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColor.brandSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 10)
            }
        }
    }

    /// Đang xem đầy đủ / đang tìm thì đóng khung 4 hàng rồi cuộn bên trong; danh sách vài
    /// chục ngân hàng mà thả tự do sẽ kéo dài lê thê cả trang.
    private var isBankListExpanded: Bool { showAllBanks || !searchQuery.isEmpty }

    private var bankGrid: some View {
        Group {
            if isBankListExpanded {
                ScrollView {
                    bankRows
                }
                // 4 ô cao 86 + 3 khoảng cách 10 — đúng 4 hàng, dư ra thì cuộn.
                .frame(maxHeight: 86 * 4 + 10 * 3)
            } else {
                bankRows
            }
        }
    }

    private var bankRows: some View {
        let rows = stride(from: 0, to: visibleBanks.count, by: Self.bankColumns).map { start in
            Array(visibleBanks[start..<min(start + Self.bankColumns, visibleBanks.count)])
        }
        return VStack(spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    ForEach(row) { bank in
                        bankCell(bank)
                    }
                    // Hàng cuối thiếu ô thì chèn chỗ trống, không thì ô cuối bị kéo giãn.
                    ForEach(0..<(Self.bankColumns - row.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func bankCell(_ bank: Bank) -> some View {
        let isSelected = selectedBank?.bin == bank.bin
        return Button {
            selectedBank = bank
            accName = ""
            lookupError = nil
            if accNo.count >= 4 { runLookup() }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    BankLogoView(bank: bank, size: 38)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AppColor.brand)
                            .padding(2)
                            .background(Color.white, in: Circle())
                    }
                }
                .frame(width: 40, height: 40)

                Text(bank.shortName)
                    .font(AppFont.beVietnamPro(9, .semibold))
                    .foregroundStyle(AppColor.payInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            // Cao cố định để khung cuộn 4 hàng tính đúng, tên ngân hàng dài ngắn khác
            // nhau cũng không làm hàng cao thấp so le.
            .frame(maxWidth: .infinity)
            .frame(height: 86)
            .padding(.horizontal, 8)
            .background(isSelected ? AppColor.brandSoft : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? AppColor.brand : AppColor.payInputBorder,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private var accountField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Số tài khoản")
                .font(AppFont.beVietnamPro(12, .semibold))
                .foregroundStyle(AppColor.payInk)

            TextField("Nhập số tài khoản", text: $accNo)
                .font(AppFont.beVietnamPro(14))
                .foregroundStyle(AppColor.payInk)
                .tint(AppColor.brand)
                .keyboardType(.numberPad)
                .focused($isAccountFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 48)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AppColor.payInputBorder, lineWidth: 1)
                }
                .onChange(of: accNo) { _, newValue in
                    let digits = newValue.filter(\.isNumber)
                    if digits != newValue { accNo = digits }
                    accName = ""
                    lookupError = nil
                }
                // Chỉ tra khi đã nhập XONG (rời focus) — gọi theo từng ký tự vừa tốn
                // request vừa hiện tên sai lúc số còn gõ dở.
                .onChange(of: isAccountFocused) { wasFocused, focused in
                    if wasFocused && !focused { runLookup() }
                }
        }
    }

    // MARK: - Nút nộp

    private var submitButton: some View {
        Button(action: submit) {
            Text(isSubmitting ? "Đang nộp hồ sơ..." : "Hoàn tất xác thực")
                .font(AppFont.beVietnamPro(16, .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AppColor.brand.opacity(canSubmit ? 1 : 0.45))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .primaryButtonShadow()
    }

    private var verifyingOverlay: some View {
        ZStack {
            Color.white.opacity(0.8)
            VStack(spacing: 16) {
                ProgressView().progressViewStyle(.circular).tint(AppColor.brand)
                Text("Đang xác thực CCCD…")
                    .font(AppFont.beVietnamPro(15, .medium))
                    .foregroundStyle(AppColor.payInk)
            }
        }
        // Nuốt chạm để chặn thao tác nền trong lúc đối soát. Phải ép ZStack giãn hết
        // khung TRƯỚC khi `contentShape` — không thì ZStack chỉ to bằng nội dung, để hở
        // vùng nút back phía trên và chạm vào đó sẽ thoát về màn quét CCCD giữa lúc chờ.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {}
        .ignoresSafeArea()
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppColor.payInputBorder, lineWidth: 1)
        }
        .inputShadow()
    }

    // MARK: - Nghiệp vụ

    /// Đối soát chữ ký số trên chip. Không có dữ liệu chip thì không đối soát được —
    /// bắt quét lại chứ không cho đi tiếp với hồ sơ chưa xác thực.
    private func verifyC06() async {
        defer { isVerifyingC06 = false }
        guard let nfcRawData = pending.nfcRawJson, !nfcRawData.isEmpty else {
            c06Error = "Thiếu dữ liệu chip NFC, vui lòng quét lại CCCD."
            return
        }
        do {
            let result = try await OnboardingService.verifyC06(
                ekycSessionId: EkycSessionManager.shared.session?.ekycSessionId,
                idCard: pending.idCardNumber,
                nfcRawData: nfcRawData
            )
            if !result.approved {
                c06Error = "Thẻ CCCD không hợp lệ (\(result.decision ?? "invalid")). Vui lòng thử lại."
            }
        } catch let error as APIError {
            c06Error = error.message
        } catch {
            c06Error = "Không xác thực được thẻ CCCD, vui lòng thử lại."
        }
    }

    private func runLookup() {
        guard let bank = selectedBank, accNo.count >= 4, !isLookingUp else { return }
        let key = "\(bank.bin)|\(accNo)"
        if lastLookedUp == key { return }
        lastLookedUp = key
        isLookingUp = true
        lookupError = nil
        accName = ""
        Task {
            defer { isLookingUp = false }
            do {
                accName = try await TransferService.verifyBeneficiary(
                    VerifyBeneficiaryRequest(accNo: accNo, bankNo: Int(bank.bin), accType: 0)
                )
            } catch let error as APIError {
                lookupError = error.message
            } catch {
                lookupError = "Tài khoản không hợp lệ"
            }
        }
    }

    private func submit() {
        guard canSubmit, let bank = selectedBank else { return }
        submitError = nil

        pending.temporaryLocation = temporaryLocation.trimmingCharacters(in: .whitespaces)
        pending.business = business
        pending.position = position
        pending.purposeOfUsing = purposeOfUsing
        pending.businessAreaId = businessAreaId

        guard let snapshot = pending.snapshot() else {
            submitError = "Thiếu dữ liệu từ CCCD, vui lòng quét lại thẻ"
            return
        }

        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                let result = try await OnboardingService.submitEkyc(
                    payload: snapshot, bankNo: bank.bin, accNo: accNo, accName: accName
                )
                let failing = result.fieldsNeedingFix
                if failing.isEmpty {
                    onSubmitted()
                } else {
                    fieldsToFix = failing
                }
            } catch let error as APIError {
                submitError = error.message
            } catch {
                submitError = "Nộp hồ sơ thất bại, vui lòng thử lại"
            }
        }
    }
}

#Preview {
    KycReviewView(onBack: {}, onSubmitted: {})
}
