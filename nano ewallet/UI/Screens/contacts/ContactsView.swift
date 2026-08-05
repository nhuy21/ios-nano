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

struct ContactsView: View {
    let onBack: () -> Void
    /// Lọc theo loại khi mở từ 1 luồng cụ thể — nil = hiện cả 2 loại.
    var filterType: BeneficiaryType?
    var onPickForTransfer: (Beneficiary) -> Void = { _ in }
    var onPickForWalletTransfer: (_ name: String, _ sub: String) -> Void = { _, _ in }
    var onPickForRequest: (_ name: String, _ bkUsername: String) -> Void = { _, _ in }

    @StateObject private var store = BeneficiaryStore.shared
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var actionTarget: Beneficiary?
    @State private var editTarget: Beneficiary?

    private var title: String {
        switch filterType {
        case .bankAccount: return "DANH BẠ NGÂN HÀNG"
        case .wallet: return "DANH BẠ VÍ"
        case .none: return "DANH BẠ"
        }
    }

    private var typedContacts: [Beneficiary] {
        guard let filterType else { return store.beneficiaries }
        return store.beneficiaries.filter { $0.type == filterType }
    }

    private var filtered: [Beneficiary] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return typedContacts }
        return typedContacts.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed)
                || ($0.accNo?.contains(trimmed) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            content
        }
        .background(Color(hex: 0xF7F8FA))
        .task { _ = await store.get() }
        .sheet(isPresented: $showAdd) {
            AddContactSheet(onSaved: {
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
            .buttonStyle(.plain)

            Spacer()

            Text(title)
                .font(AppFont.beVietnamPro(15, .bold))
                .foregroundStyle(.white)
                .tracking(2)

            Spacer()

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
            .buttonStyle(.plain)
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

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(AppColor.payMuted)
            TextField("", text: $searchText, prompt: .appPlaceholder("Tìm theo tên, số tài khoản..."))
                .font(AppFont.beVietnamPro(14))
                .foregroundStyle(AppColor.payInk)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark").foregroundStyle(AppColor.payMuted)
                }
                .buttonStyle(.plain)
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
            message(
                title: "Danh bạ trống",
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
                    .buttonStyle(.plain)
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
            .buttonStyle(.plain)
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

#Preview {
    ContactsView(onBack: {})
}
