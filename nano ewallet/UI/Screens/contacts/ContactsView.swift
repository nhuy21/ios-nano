//
//  ContactsView.swift
//  nano ewallet
//
//  Mirror ContactsScreen.kt — danh bạ người thụ hưởng, dùng chung cho 3 luồng pick
//  (chuyển khoản ngân hàng, chuyển ví, xin tiền). Header gradient xanh lá riêng
//  (khác style trắng chuẩn của các màn khác — đúng bản gốc).
//

import SwiftUI
import Combine
import UIKit

struct ContactsView: View {
    let onBack: () -> Void
    /// Khoá theo loại khi mở từ 1 luồng cụ thể — nil = mở từ Trang chủ, hiện tab cho user
    /// tự chọn loại. Danh sách LUÔN chỉ hiện một loại tại một thời điểm.
    var filterType: BeneficiaryType?
    var onPickForTransfer: (Beneficiary) -> Void = { _ in }
    var onPickForWalletTransfer: (_ name: String, _ sub: String) -> Void = { _, _ in }
    var onPickForRequest: (_ name: String, _ bkUsername: String) -> Void = { _, _ in }
    /// Mở màn "Tìm bạn trong danh bạ". Chỉ hiện khi mở từ Trang chủ (`filterType == nil`) —
    /// vào từ một luồng chuyển tiền cụ thể thì người dùng đang chọn người nhận, chen thêm
    /// một màn khác vào là lạc đề.
    var onFindFriends: () -> Void = {}

    @StateObject private var store = BeneficiaryStore.shared
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var actionTarget: Beneficiary?
    @State private var editTarget: Beneficiary?
    /// Tab đang chọn khi mở từ Trang chủ (`filterType == nil`). Mặc định ví vì đây là
    /// loại chuyển tiền chính của app, ngân hàng chỉ là kênh phụ.
    @State private var selectedType: BeneficiaryType = .wallet

    /// Loại đang hiển thị thật sự: luồng chuyển tiền khoá cứng, còn lại theo tab.
    private var activeType: BeneficiaryType { filterType ?? selectedType }

    private var title: String {
        switch filterType {
        case .bankAccount: return "DANH BẠ NGÂN HÀNG"
        case .wallet: return "DANH BẠ VÍ"
        case .none: return "DANH BẠ"
        }
    }

    private var typedContacts: [Beneficiary] {
        store.beneficiaries.filter { $0.type == activeType }
    }

    private var filtered: [Beneficiary] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return typedContacts }
        return typedContacts.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed)
                || ($0.accNo?.contains(trimmed) ?? false)
                // Liên hệ ví không có accNo — thiếu vế này thì gõ số ví không ra kết quả nào.
                || ($0.benUsername?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            // Chỉ mở từ Trang chủ mới cho đổi loại; vào từ luồng chuyển tiền thì loại đã
            // do luồng quyết định, hiện tab ở đây chỉ tạo cơ hội chọn nhầm.
            if filterType == nil {
                typePicker
            }
            searchBar
            content
        }
        .screenBackground(Color(hex: 0xF7F8FA))
        .task { _ = await store.get() }
        .sheet(isPresented: $showAdd) {
            // Chọn loại nằm NGAY trong form, không tách thành một sheet hỏi trước: bớt
            // một lớp bấm, và đổi ý giữa chừng thì đổi tại chỗ chứ không phải thoát ra.
            AddContactSheet(initialType: activeType, isTypeLocked: filterType != nil, onSaved: {
                showAdd = false
                Task { await store.refresh() }
            }, onCancel: { showAdd = false })
        }
        .sheet(item: $actionTarget) { contact in
            ContactActionSheet(
                contact: contact,
                onTransfer: { transfer(contact) },
                onRequest: {
                    actionTarget = nil
                    if let username = contact.benUsername {
                        onPickForRequest(contact.displayName, username)
                    }
                },
                onEditNickname: {
                    actionTarget = nil
                    editTarget = contact
                },
                onDelete: {
                    actionTarget = nil
                    Task { try? await store.delete(id: contact.id) }
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(item: $editTarget) { contact in
            EditNicknameSheet(
                initialValue: contact.nickname ?? "",
                onSave: { newValue in
                    editTarget = nil
                    Task { try? await store.updateNickname(id: contact.id, nickname: newValue) }
                },
                onCancel: { editTarget = nil }
            )
            .presentationDetents([.height(240)])
        }
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
            .buttonStyle(PressableButtonStyle())

            Spacer()

            Text(title)
                .font(AppFont.beVietnamPro(15, .bold))
                .foregroundStyle(.white)
                .tracking(2)

            Spacer()

            // Chỉ hiện khi mở từ Trang chủ: vào từ một luồng chuyển tiền thì người dùng đang
            // chọn người nhận, chen thêm màn khác vào là lạc đề.
            if filterType == nil {
                Button(action: onFindFriends) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Tìm bạn trong danh bạ")
            }

            Button {
                showAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Thêm")
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

    /// Tab Ví / Ngân hàng — hai loại người nhận dùng API và màn chuyển tiền khác hẳn nhau
    /// nên tách hẳn danh sách thay vì trộn chung rồi phân biệt bằng dòng phụ đề.
    ///
    /// Tự vẽ thay `Picker(.segmented)`: segmented control của hệ thống ghim cứng chiều cao
    /// ~32pt, không nới ra được, nhìn chật so với phần còn lại của màn.
    private var typePicker: some View {
        HStack(spacing: 6) {
            typeTab(.wallet, title: "Ví")
            typeTab(.bankAccount, title: "Ngân hàng")
        }
        .padding(4)
        .background(Color(hex: 0xEDEFF2))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    /// Mở từ một luồng chuyển tiền cụ thể thì loại đã bị khoá — hỏi lại là thừa, mà chọn
    /// nhầm loại còn dẫn người dùng vào màn chuyển tiền sai. Chỉ hỏi khi vào từ Trang chủ.
    private func typeTab(_ type: BeneficiaryType, title: String) -> some View {
        let isSelected = selectedType == type
        return Button {
            selectedType = type
        } label: {
            Text(title)
                .font(AppFont.beVietnamPro(14, isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AppColor.payInk : AppColor.payMuted)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isSelected ? Color.white : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(AppColor.payMuted)
            TextField(
                "", text: $searchText,
                prompt: .appPlaceholder(
                    activeType == .wallet ? "Tìm theo tên, số ví..." : "Tìm theo tên, số tài khoản..."
                )
            )
                .font(AppFont.beVietnamPro(14))
                .foregroundStyle(AppColor.payInk)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark").foregroundStyle(AppColor.payMuted)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Xoá")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppColor.payInputBorder, lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Nội dung

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.beneficiaries.isEmpty {
            ProgressView().tint(AppColor.brand).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = store.loadError, store.beneficiaries.isEmpty {
            message(
                title: "Không tải được danh bạ", subtitle: error,
                actionTitle: "Thử lại", action: { Task { await store.refresh() } }
            )
        } else if typedContacts.isEmpty {
            // Nói rõ đang trống loại NÀO: user có thể đã lưu liên hệ ở tab kia và tưởng
            // danh bạ mất sạch.
            message(
                title: activeType == .wallet ? "Chưa có liên hệ ví nào" : "Chưa có liên hệ ngân hàng nào",
                subtitle: "Thêm người nhận để chuyển tiền nhanh hơn lần sau",
                actionTitle: "Thêm người nhận", action: { showAdd = true }
            )
        } else if filtered.isEmpty {
            message(
                title: "Không tìm thấy",
                subtitle: "Không có người nhận nào khớp \"\(searchText)\"",
                actionTitle: nil, action: nil
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { contact in
                        contactRow(contact)
                        Rectangle().fill(AppColor.line).frame(height: 1).padding(.leading, 68)
                    }
                }
                .padding(.horizontal, 16)
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 24) }
        }
    }

    private func message(title: String, subtitle: String, actionTitle: String?, action: (() -> Void)?) -> some View {
        VStack(spacing: 12) {
            Circle()
                .fill(AppColor.brandSoft)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(AppColor.brand)
                }
            Text(title)
                .font(AppFont.beVietnamPro(15, .semibold))
                .foregroundStyle(AppColor.payInk)
            Text(subtitle)
                .font(AppFont.beVietnamPro(13))
                .foregroundStyle(AppColor.payMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PressableButtonStyle())
                    .font(AppFont.beVietnamPro(14, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(AppColor.brand)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }

    private func contactRow(_ contact: Beneficiary) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(avatarColor(for: contact.displayName))
                .frame(width: 44, height: 44)
                .overlay {
                    Text(initials(for: contact.displayName))
                        .font(AppFont.beVietnamPro(16, .bold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName)
                    .font(AppFont.beVietnamPro(15, .semibold))
                    .foregroundStyle(AppColor.payInk)
                Text(subtitle(for: contact))
                    .font(AppFont.beVietnamPro(12))
                    .foregroundStyle(AppColor.payMuted)
            }

            Spacer()

            Button {
                actionTarget = contact
            } label: {
                // Material "MoreVert" là 3 chấm DỌC — SF Symbol "ellipsis" mặc định nằm
                // ngang, xoay 90° để đúng ý nghĩa gốc.
                Image(systemName: "ellipsis")
                    .font(.system(size: 16))
                    .rotationEffect(.degrees(90))
                    .foregroundStyle(AppColor.payMuted)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { transfer(contact) }
    }

    private func subtitle(for contact: Beneficiary) -> String {
        var base: String
        switch contact.type {
        case .wallet:
            base = "Ví nano · \(contact.benUsername ?? "")"
        case .bankAccount:
            let bankName = BankCache.shared.bank(bin: contact.bankNo)?.shortName ?? "Ngân hàng"
            base = "\(bankName) · \(contact.accNo ?? "")"
        }
        if let nickname = contact.nickname, !nickname.isEmpty, nickname != contact.displayName {
            base += " · \(nickname)"
        }
        return base
    }

    // MARK: - Actions

    private func transfer(_ contact: Beneficiary) {
        actionTarget = nil
        store.touch(id: contact.id)
        switch contact.type {
        case .wallet:
            onPickForWalletTransfer(contact.displayName, "@\(contact.benUsername ?? "")")
        case .bankAccount:
            onPickForTransfer(contact)
        }
    }

    private func initials(for name: String) -> String {
        name.nameInitials
    }

    private static let avatarColors: [Color] = [
        Color(hex: 0xF5901E), Color(hex: 0x22A45D), Color(hex: 0x2C93E8),
        Color(hex: 0x6A6AF5), Color(hex: 0xE5484D), Color(hex: 0x1A3FBF),
        Color(hex: 0x00A85E), Color(hex: 0xE8531F),
    ]

    private func avatarColor(for name: String) -> Color {
        let hash = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Self.avatarColors[hash % Self.avatarColors.count]
    }
}

// MARK: - Tìm bạn trong danh bạ

/// Đối chiếu số điện thoại trong danh bạ MÁY với người đã dùng nano.
///
/// Màn giải thích hiện TRƯỚC hộp thoại quyền của hệ thống: bung thẳng hộp thoại thì người dùng
/// không biết app sẽ làm gì với danh bạ nên dễ từ chối, mà iOS chỉ cho hỏi MỘT lần — từ chối
/// rồi thì hộp thoại không hiện lại nữa, nút "Thử lại" sẽ thành nút chết. Vì vậy khi đã bị từ
/// chối, nút đổi thành "Mở Cài đặt".
struct FindFriendsView: View {
    let onBack: () -> Void
    /// Chọn một người -> mở màn chuyển tiền ví.
    var onTransfer: (WalletTransferDraft) -> Void = { _ in }

    @StateObject private var store = BeneficiaryStore.shared
    @StateObject private var toast = ToastState()

    @State private var status = PhoneContacts.authorizationStatus
    @State private var isScanning = false
    @State private var friends: [MatchedFriend]?
    /// Tên trong danh bạ MÁY theo số — hiện kèm tên trên ví để người dùng nhận ra ai.
    @State private var localNames: [String: String] = [:]
    /// Số lô bị bỏ vì lỗi mạng — phải nói ra, không được im lặng trả thiếu người.
    @State private var skippedBatches = 0
    @State private var errorMessage: String?
    @State private var search = ""
    @State private var savedUsernames: Set<String> = []
    @State private var savingUsername: String?

    /// BE nhận tối đa 200 số mỗi lượt (`ArrayMaxSize`).
    private static let batchSize = 200

    private var visible: [MatchedFriend] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty, let friends else { return friends ?? [] }
        return friends.filter {
            $0.accName.lowercased().contains(query)
                || (localNames[$0.phone] ?? "").lowercased().contains(query)
                || $0.phone.contains(query)
                || $0.benUsername.contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(title: "Tìm bạn trong danh bạ", onBack: onBack)
            content
        }
        .screenBackground(Color.white)
        .toast(toast, bottomPadding: 24)
    }

    @ViewBuilder
    private var content: some View {
        if isScanning {
            scanning
        } else if let friends {
            results(friends)
        } else {
            intro
        }
    }

    // MARK: - Màn giải thích

    private var intro: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "person.2.fill")
                .font(.system(size: 44))
                .foregroundStyle(AppColor.brand)
                .frame(width: 92, height: 92)
                .background(AppColor.brandSoft, in: Circle())

            Text("Tìm bạn bè đã dùng Ví nano")
                .font(AppFont.beVietnamPro(18, .bold))
                .foregroundStyle(AppColor.payInk)
                .padding(.top, 20)

            Text("Ví nano sẽ đối chiếu số điện thoại trong danh bạ của bạn để tìm những người đã có ví.")
                .font(AppFont.beVietnamPro(14))
                .foregroundStyle(AppColor.payMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 32)

            // Nói rõ app KHÔNG làm gì — đây là dữ liệu của người thứ ba, họ không đồng ý gì
            // với app này nên người dùng có quyền biết trước khi cho đọc.
            VStack(alignment: .leading, spacing: 10) {
                promise("Chỉ đọc tên và số điện thoại")
                promise("Dùng cho một lần đối chiếu rồi bỏ")
                promise("Không lưu danh bạ của bạn lên máy chủ")
            }
            .padding(.top, 24)
            .padding(.horizontal, 32)

            Spacer()

            if let errorMessage {
                Text(errorMessage)
                    .font(AppFont.beVietnamPro(13))
                    .foregroundStyle(AppColor.error)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }

            PrimaryButton(title: primaryTitle) {
                Task { await start() }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    /// Bị từ chối VĨNH VIỄN thì hộp thoại hệ thống không hiện lại nữa — nút "Thử lại" sẽ là
    /// nút chết, nên đổi hẳn sang mở Cài đặt.
    private var primaryTitle: String {
        switch status {
        case .denied, .restricted: return "Mở Cài đặt"
        default: return "Tìm bạn trong danh bạ"
        }
    }

    private func promise(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(AppColor.brand)
            Text(text)
                .font(AppFont.beVietnamPro(13.5))
                .foregroundStyle(AppColor.payMuted)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Đang quét

    private var scanning: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().tint(AppColor.brand).scaleEffect(1.2)
            Text("Đang đối chiếu danh bạ...")
                .font(AppFont.beVietnamPro(14))
                .foregroundStyle(AppColor.payMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Kết quả

    @ViewBuilder
    private func results(_ all: [MatchedFriend]) -> some View {
        if all.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Text("Chưa có ai trong danh bạ dùng Ví nano")
                    .font(AppFont.beVietnamPro(15, .semibold))
                    .foregroundStyle(AppColor.payInk)
                if skippedBatches > 0 {
                    Text(skippedWarning)
                        .font(AppFont.beVietnamPro(13))
                        .foregroundStyle(AppColor.payMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 0) {
                searchBar

                if skippedBatches > 0 {
                    Text(skippedWarning)
                        .font(AppFont.beVietnamPro(12.5))
                        .foregroundStyle(AppColor.payMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { friend in
                            row(friend)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    /// Nói rõ kết quả CHƯA đầy đủ. Im lặng trả thiếu người thì người dùng tưởng bạn mình chưa
    /// dùng app, trong khi thật ra là lỗi mạng.
    private var skippedWarning: String {
        "Có \(skippedBatches) nhóm số chưa đối chiếu được do lỗi mạng, danh sách có thể còn thiếu."
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(AppColor.payMuted)
            TextField("", text: $search, prompt: .appPlaceholder("Tìm theo tên hoặc số"))
                .font(AppFont.beVietnamPro(14))
                .foregroundStyle(AppColor.payInk)
                .tint(AppColor.brand)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(AppColor.bgSoft)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func row(_ friend: MatchedFriend) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(AppColor.brandSoft)
                .frame(width: 42, height: 42)
                .overlay {
                    Text(displayName(friend).nameInitials)
                        .font(AppFont.beVietnamPro(15, .bold))
                        .foregroundStyle(AppColor.brand)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(friend))
                    .font(AppFont.beVietnamPro(14, .semibold))
                    .foregroundStyle(AppColor.payInk)
                    .lineLimit(1)
                // Tên trên VÍ có thể khác tên trong danh bạ máy — hiện cả hai để người dùng
                // biết chắc đang chuyển cho ai.
                Text(friend.accName)
                    .font(AppFont.beVietnamPro(12))
                    .foregroundStyle(AppColor.payMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            actions(friend)
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func actions(_ friend: MatchedFriend) -> some View {
        HStack(spacing: 8) {
            if savingUsername == friend.benUsername {
                ProgressView().tint(AppColor.brand)
            } else if savedUsernames.contains(friend.benUsername) || isInContacts(friend) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(AppColor.brand)
            } else {
                Button {
                    Task { await save(friend) }
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 18))
                        .foregroundStyle(AppColor.brand)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Lưu vào danh bạ")
            }

            Button {
                onTransfer(WalletTransferDraft(
                    username: friend.benUsername,
                    holderName: friend.accName,
                    payLinkToken: nil,
                    prefillAmount: nil
                ))
            } label: {
                Text("Chuyển tiền")
                    .font(AppFont.beVietnamPro(13, .bold))
                    .foregroundStyle(AppColor.brand)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColor.brandSoft, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
        }
    }

    private func displayName(_ friend: MatchedFriend) -> String {
        let local = localNames[friend.phone]?.trimmingCharacters(in: .whitespaces) ?? ""
        return local.isEmpty ? friend.accName : local
    }

    private func isInContacts(_ friend: MatchedFriend) -> Bool {
        store.beneficiaries.contains { $0.benUsername == friend.benUsername }
    }

    // MARK: - Hành động

    private func start() async {
        errorMessage = nil

        // Đã từ chối vĩnh viễn -> hộp thoại không hiện lại được, chỉ còn đường vào Cài đặt.
        if status == .denied || status == .restricted {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
            return
        }

        if status != .authorized {
            let granted = await PhoneContacts.requestAccess()
            status = PhoneContacts.authorizationStatus
            guard granted else {
                errorMessage = "Cần quyền đọc danh bạ để tìm bạn bè."
                return
            }
        }

        isScanning = true
        defer { isScanning = false }

        let contacts = await PhoneContacts.readAll()
        guard !contacts.isEmpty else {
            friends = []
            return
        }
        localNames = Dictionary(contacts.map { ($0.phone, $0.name) }, uniquingKeysWith: { first, _ in first })

        var matched: [MatchedFriend] = []
        var skipped = 0
        // Chia lô vì BE chặn 200 số mỗi lượt. Một lô lỗi thì BỎ QUA lô đó chứ không huỷ cả
        // lượt — danh bạ vài nghìn số mà hỏng một lô là mất trắng thì quá phí.
        for batch in stride(from: 0, to: contacts.count, by: Self.batchSize) {
            let slice = contacts[batch..<min(batch + Self.batchSize, contacts.count)]
            do {
                matched += try await BeneficiaryService.matchContacts(phones: slice.map(\.phone))
            } catch {
                skipped += 1
            }
        }

        // Bỏ trùng: một người có thể lưu nhiều số trong danh bạ.
        var seen = Set<String>()
        friends = matched.filter { seen.insert($0.benUsername).inserted }
        skippedBatches = skipped

        // Nạp danh bạ nano để biết ai đã lưu rồi — nếu không thì nút "Lưu" hiện cả với người
        // đã có trong danh bạ.
        _ = await store.get()
    }

    private func save(_ friend: MatchedFriend) async {
        savingUsername = friend.benUsername
        defer { savingUsername = nil }
        do {
            _ = try await store.create(CreateBeneficiaryRequest(
                type: .wallet,
                bankNo: nil,
                accNo: nil,
                accName: friend.accName,
                benUsername: friend.benUsername,
                // Tên trong danh bạ MÁY làm tên gợi nhớ — đó là cái người dùng quen gọi.
                nickname: localNames[friend.phone]
            ))
            savedUsernames.insert(friend.benUsername)
            toast.show("Đã lưu vào danh bạ")
        } catch {
            toast.show("Không lưu được, vui lòng thử lại")
        }
    }
}

#Preview {
    ContactsView(onBack: {})
}
