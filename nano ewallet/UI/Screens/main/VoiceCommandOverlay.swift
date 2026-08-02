//
//  VoiceCommandOverlay.swift
//  nano ewallet
//
//  Mirror VoiceCommandOverlay.kt — nghe "chuyển 200 nghìn cho Mẹ", khớp danh bạ ví
//  rồi đưa sang màn nhập tiền với người nhận + số tiền điền sẵn.
//
//  KHÔNG tự chuyển tiền: người dùng vẫn xác nhận và nhập PIN ở màn sau.
//

import SwiftUI
import Combine

@MainActor
struct VoiceCommandOverlay: View {
    let onDismiss: () -> Void
    let onResolved: (WalletTransferDraft) -> Void

    @StateObject private var speech = SpeechRecognizerService()
    @StateObject private var beneficiaryStore = BeneficiaryStore.shared

    @State private var statusMessage: String?
    /// Mic đập nhẹ khi đang nghe.
    @State private var pulse = false

    private var walletContacts: [Beneficiary] {
        beneficiaryStore.beneficiaries.filter {
            $0.type == .wallet && !($0.benUsername ?? "").isEmpty
        }
    }

    private var heard: String { speech.partialText.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { close() }

            panel
                .padding(.horizontal, 28)
                // Chặn tap xuyên xuống lớp nền (chạm trong panel không đóng).
                .onTapGesture {}
        }
        .task {
            _ = await beneficiaryStore.get()
            await speech.start()
        }
        .onDisappear { speech.stop() }
        .onAppear {
            speech.onResult = { candidates in handleResult(candidates) }
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(AppColor.brand)
                .frame(width: 76, height: 76)
                .overlay {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white)
                }
                .scaleEffect(speech.isListening && pulse ? 1.18 : 1)
                .animation(
                    speech.isListening
                        ? .easeInOut(duration: 0.65).repeatForever(autoreverses: true)
                        : .default,
                    value: pulse
                )
                .onAppear { pulse = true }

            Text(title)
                .font(AppFont.beVietnamPro(18, .bold))
                .foregroundStyle(AppColor.payInk)
                .padding(.top, 16)

            Text(bodyText)
                .font(AppFont.beVietnamPro(14))
                .foregroundStyle(bodyIsError ? Color(hex: 0xE5484D) : AppColor.payMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 8)

            // Nghe được chữ NHƯNG không khớp -> hiện cả hai: câu đã nghe ở trên,
            // lý do thất bại ở đây. Nếu gộp một chỗ thì mất một trong hai.
            if let statusMessage, !heard.isEmpty {
                Text(statusMessage)
                    .font(AppFont.beVietnamPro(13))
                    .foregroundStyle(Color(hex: 0xE5484D))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.top, 6)
            }

            HStack(spacing: 12) {
                actionButton(
                    title: "Nói lại",
                    foreground: AppColor.brand,
                    background: AppColor.brand.opacity(0.12)
                ) {
                    statusMessage = nil
                    Task { await speech.start() }
                }

                actionButton(
                    title: "Đóng",
                    foreground: AppColor.payInk,
                    background: Color(hex: 0xF1F3F5),
                    action: close
                )
            }
            .padding(.top, 20)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func actionButton(
        title: String, foreground: Color, background: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.beVietnamPro(15, .bold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Trạng thái hiển thị

    private var title: String {
        speech.isListening ? "Đang nghe…" : "Trợ lý Ví nano"
    }

    private var bodyText: String {
        if !heard.isEmpty { return heard }
        if let error = speech.errorMessage { return error }
        if let statusMessage { return statusMessage }
        return "Hãy nói, ví dụ: \"chuyển 200 nghìn cho Mẹ\""
    }

    private var bodyIsError: Bool {
        heard.isEmpty && (speech.errorMessage != nil || statusMessage != nil)
    }

    // MARK: - Xử lý

    private func handleResult(_ candidates: [String]) {
        switch VoiceCommandResolver.resolve(candidates: candidates, contacts: walletContacts) {
        case .wallet(let draft):
            speech.stop()
            onResolved(draft)
        case .failure(let message):
            statusMessage = message
        }
    }

    private func close() {
        speech.stop()
        onDismiss()
    }
}
