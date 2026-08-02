//
//  WalletTransferView.swift
//  nano ewallet
//
//  Mirror WalletTransferScreen.kt — nhập username ví Bảo Kim, verify qua
//  wallet/verify-beneficiary rồi chuyển sang WalletTransferAmountView.
//

import SwiftUI
import Combine
import UIKit

/// Bảng màu riêng của màn này.
private enum WtColor {
    static let pageBg = Color(hex: 0xF4F5F6)
    static let green = Color(hex: 0x00A85E)
    static let ink = Color(hex: 0x111C17)
    static let gray = Color(hex: 0x8A9990)
    static let fieldFill = Color(hex: 0xF1F3F5)
    static let circleBg = Color(hex: 0xF1F3F5)

    /// Màu avatar gán ổn định theo tên người nhận.
    static let avatarColors: [Color] = [
        Color(hex: 0xB5E48C), Color(hex: 0xA0C4FF), Color(hex: 0xFFB4A2),
        Color(hex: 0xBDB2FF), Color(hex: 0xFFD6A5), Color(hex: 0x9BF6FF),
    ]

    static func avatar(for name: String) -> Color {
        let hash = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return avatarColors[hash % avatarColors.count]
    }
}

/// Thẻ trắng bo 20 có bóng nhẹ — dùng chung cho 2 khối của màn.
private extension View {
    func wtCard() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
    }
}

@MainActor
struct WalletTransferView: View {
    let onBack: () -> Void
    var initialDraft: WalletTransferDraft?
    let onContinue: (WalletTransferDraft) -> Void
    /// Mở màn Danh bạ — dùng cho cả link "Danh bạ" ở card nhập lẫn "Xem tất cả".
    var onOpenContacts: () -> Void = {}

    @StateObject private var beneficiaryStore = BeneficiaryStore.shared

    @State private var username = ""
    @State private var isVerifying = false
    @State private var errorMessage: String?
    @State private var verifiedName: String?
    @State private var lastVerified: String?
    @State private var showSupport = false

    @FocusState private var isFocused: Bool

    private var recentWalletContacts: [Beneficiary] {
        beneficiaryStore.beneficiaries.filter { $0.type == .wallet }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        usernameSection
                        recentSection
                    }
                    .padding(16)
                }
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 24) }
                continueBar
            }
            .background(WtColor.pageBg)

            if showSupport {
                SupportDialog(onDismiss: { showSupport = false })
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.18), value: showSupport)
        .task { await beneficiaryStore.refresh() }
        .onAppear {
            if let initialDraft {
                username = initialDraft.username
                verifiedName = initialDraft.holderName
                lastVerified = initialDraft.username
            }
        }
    }

    // MARK: - Header

    /// Header TRẮNG chữ tối, tiêu đề "Chuyển tiền ví" canh giữa — không còn dải
    /// gradient xanh.
    private var header: some View {
        ZStack {
            Text("Chuyển tiền ví")
                .font(AppFont.beVietnamPro(18, .bold))
                .foregroundStyle(WtColor.ink)

            HStack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(WtColor.ink)
                        .frame(width: 44, height: 44)
                        .background(WtColor.circleBg)
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quay lại")

                Spacer()

                Button { showSupport = true } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(WtColor.gray)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white)
    }

    // MARK: - Username

    private var usernameSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Số ví người nhận")
                    .font(AppFont.beVietnamPro(14, .bold))
                    .foregroundStyle(WtColor.ink)
                Spacer()
                Button { onOpenContacts() } label: {
                    HStack(spacing: 2) {
                        Text("Danh bạ")
                            .font(AppFont.beVietnamPro(13, .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(WtColor.green)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer().frame(height: 10)

            // Ô nhập + nút "Dán" nằm TRONG ô (không phải nút rời bên cạnh).
            HStack(spacing: 8) {
                TextField("", text: $username, prompt: Text("Nhập số ví")
                    .font(AppFont.beVietnamPro(15))
                    .foregroundColor(WtColor.gray))
                    .font(AppFont.beVietnamPro(15, .semibold))
                    .foregroundStyle(WtColor.ink)
                    .keyboardType(.numberPad)
                    .tint(WtColor.green)
                    .focused($isFocused)
                    .onChange(of: isFocused) { wasFocused, isFocusedNow in
                        if wasFocused && !isFocusedNow { runVerifyIfNeeded() }
                    }

                Button {
                    if let clip = UIPasteboard.general.string { username = clip }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 15))
                        Text("Dán")
                            .font(AppFont.beVietnamPro(12.5, .bold))
                    }
                    .foregroundStyle(WtColor.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(WtColor.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .frame(height: 52)
            .background(WtColor.fieldFill)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Spacer().frame(height: 16)

            Text("Tên chủ ví")
                .font(AppFont.beVietnamPro(14, .bold))
                .foregroundStyle(WtColor.ink)

            Spacer().frame(height: 10)

            // Ô tên chủ ví là ô CHỈ ĐỌC, luôn hiện — hiển thị trạng thái tra cứu.
            HStack(spacing: 8) {
                if isVerifying {
                    ProgressView()
                        .controlSize(.small)
                        .tint(WtColor.green)
                    Text("Đang tra cứu...")
                        .font(AppFont.beVietnamPro(13))
                        .foregroundStyle(WtColor.gray)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(AppFont.beVietnamPro(13))
                        .foregroundStyle(AppColor.error)
                        .lineLimit(2)
                } else if let verifiedName {
                    Text(verifiedName)
                        .font(AppFont.beVietnamPro(15, .semibold))
                        .foregroundStyle(WtColor.ink)
                        .lineLimit(1)
                } else {
                    Text("Nhập username để tra cứu")
                        .font(AppFont.beVietnamPro(13))
                        .foregroundStyle(WtColor.gray)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(WtColor.fieldFill)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .wtCard()
    }

    // MARK: - Người nhận gần đây

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Người nhận gần đây")
                    .font(AppFont.beVietnamPro(15, .bold))
                    .foregroundStyle(WtColor.ink)
                Spacer()
                Button { onOpenContacts() } label: {
                    Text("Xem tất cả")
                        .font(AppFont.beVietnamPro(13, .semibold))
                        .foregroundStyle(WtColor.green)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if recentWalletContacts.isEmpty {
                Text("Chưa có người nhận nào")
                    .font(AppFont.beVietnamPro(12.5))
                    .foregroundStyle(WtColor.gray)
                    .padding(.vertical, 8)
            } else {
                ForEach(recentWalletContacts.prefix(5)) { contact in
                    let name = contact.displayName
                    Button {
                        // Người nhận đã lưu -> vào THẲNG màn nhập số tiền, không dừng
                        // lại ở bước điền username rồi phải bấm "Tiếp tục".
                        beneficiaryStore.touch(id: contact.id)
                        onContinue(WalletTransferDraft(
                            username: contact.benUsername ?? "",
                            holderName: contact.accName ?? name
                        ))
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(WtColor.avatar(for: name))
                                .frame(width: 44, height: 44)
                                .overlay {
                                    Text(name.nameInitials)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(name)
                                    .font(AppFont.beVietnamPro(14, .bold))
                                    .foregroundStyle(WtColor.ink)
                                    .lineLimit(1)
                                Text("Ví nano · \(contact.benUsername ?? "")")
                                    .font(.system(size: 12))
                                    .foregroundStyle(WtColor.gray)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 22, weight: .regular))
                                .foregroundStyle(WtColor.gray)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .wtCard()
    }

    // MARK: - Continue

    private var continueBar: some View {
        VStack(spacing: 0) {
            let enabled = verifiedName != nil && !username.isEmpty
            Button {
                guard let verifiedName else { return }
                onContinue(WalletTransferDraft(username: username, holderName: verifiedName))
            } label: {
                Text("Tiếp tục")
                    .font(AppFont.beVietnamPro(16, .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(enabled ? WtColor.green : WtColor.green.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .padding(16)
        }
        .background(WtColor.pageBg)
    }

    // MARK: - Verify

    private func runVerifyIfNeeded() {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != lastVerified else { return }
        lastVerified = trimmed
        errorMessage = nil
        verifiedName = nil
        Task {
            isVerifying = true
            defer { isVerifying = false }
            do {
                let name = try await TransferService.verifyBeneficiary(
                    VerifyBeneficiaryRequest(benUsername: trimmed)
                )
                verifiedName = name
                // Tắt cờ NGAY, trước khi chờ: `defer` chỉ chạy lúc kết thúc Task nên ô
                // "Tên chủ ví" sẽ kẹt ở "Đang tra cứu..." suốt 700ms và người dùng
                // không kịp thấy tên trước khi màn tự chuyển.
                isVerifying = false

                // Tra ra tên -> tự sang màn nhập số tiền sau ~700ms (đủ để nhìn xác
                // nhận đúng người), không phải bấm "Tiếp tục". Chỉ chạy cho lượt tra
                // cứu do người dùng nhập, không áp cho trường hợp mở màn với người
                // nhận có sẵn.
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard username.trimmingCharacters(in: .whitespaces) == trimmed,
                      verifiedName == name else { return }
                isFocused = false
                onContinue(WalletTransferDraft(username: trimmed, holderName: name))
            } catch let error as APIError {
                errorMessage = error.message
            } catch {
                errorMessage = "Không xác thực được tài khoản thụ hưởng"
            }
        }
    }
}

#Preview {
    WalletTransferView(onBack: {}, onContinue: { _ in })
}
