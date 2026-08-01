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

@MainActor
struct WalletTransferView: View {
    let onBack: () -> Void
    var initialDraft: WalletTransferDraft?
    let onContinue: (WalletTransferDraft) -> Void

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
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    usernameSection
                    if !recentWalletContacts.isEmpty {
                        recentSection
                    }
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 24) }
            continueBar
        }
        .background(Color(hex: 0xF7F8FA))
        .task { await beneficiaryStore.refresh() }
        .onAppear {
            if let initialDraft {
                username = initialDraft.username
                verifiedName = initialDraft.holderName
                lastVerified = initialDraft.username
            }
        }
        .confirmationDialog("Hỗ trợ", isPresented: $showSupport, titleVisibility: .visible) {
            Button("Gọi hotline 0966 585 328") {
                if let url = URL(string: "tel://0966585328") {
                    UIApplication.shared.open(url)
                }
            }
            Button("Đóng", role: .cancel) {}
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
            Text("CHUYỂN TIỀN")
                .font(AppFont.beVietnamPro(15, .bold))
                .foregroundStyle(.white)
                .tracking(2)
            Spacer()
            Button { showSupport = true } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
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

    // MARK: - Username

    private var usernameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: "Username ví Bảo Kim")
            HStack(spacing: 8) {
                AppTextField(
                    text: $username, placeholder: "Nhập username người nhận",
                    keyboardType: .numberPad, submitLabel: .done
                )
                .focused($isFocused)
                .onChange(of: isFocused) { wasFocused, isFocusedNow in
                    if wasFocused && !isFocusedNow { runVerifyIfNeeded() }
                }

                Button {
                    if let clip = UIPasteboard.general.string { username = clip }
                } label: {
                    Text("Dán")
                        .font(AppFont.beVietnamPro(14, .semibold))
                        .foregroundStyle(AppColor.brand)
                        .padding(.horizontal, 14)
                        .frame(height: 56)
                        .background(AppColor.brandSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if isVerifying {
                HStack(spacing: 8) {
                    ProgressView().tint(AppColor.brand)
                    Text("Đang xác thực...")
                        .font(AppFont.beVietnamPro(13))
                        .foregroundStyle(AppColor.payMuted)
                }
            } else if let errorMessage {
                FieldError(message: errorMessage, alignment: .leading)
            } else if let verifiedName {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tên chủ ví")
                        .font(AppFont.beVietnamPro(12))
                        .foregroundStyle(AppColor.payMuted)
                    Text(verifiedName)
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

    // MARK: - Người nhận gần đây

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel(text: "Người nhận gần đây").padding(.bottom, 0)
            VStack(spacing: 0) {
                ForEach(recentWalletContacts.prefix(5)) { contact in
                    Button {
                        username = contact.benUsername ?? ""
                        verifiedName = contact.displayName
                        lastVerified = username
                        errorMessage = nil
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
                                Text(contact.benUsername ?? "")
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

    // MARK: - Continue

    private var continueBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(AppColor.line).frame(height: 1)
            PrimaryButton(title: "Tiếp tục", isEnabled: verifiedName != nil && !username.isEmpty) {
                guard let verifiedName else { return }
                onContinue(WalletTransferDraft(username: username, holderName: verifiedName))
            }
            .padding(16)
        }
        .background(Color.white)
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
                verifiedName = try await TransferService.verifyBeneficiary(
                    VerifyBeneficiaryRequest(benUsername: trimmed)
                )
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
