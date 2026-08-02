//
//  CccdScanView.swift
//  nano ewallet
//
//  Mirror CccdScanScreen.kt — màn GIỚI THIỆU bước xác thực định danh. Toàn bộ việc
//  chụp CCCD / đọc NFC / xác thực khuôn mặt do SDK CmcEkyc đảm nhiệm; màn này chỉ nói
//  trước sẽ phải làm gì, CHUẨN BỊ SẴN phiên eKYC rồi mở SDK.
//
//  Phiên được lấy ngay lúc mở màn chứ không đợi bấm nút: chuỗi login/init/init-session
//  chạy phía BE mất vài giây, để tới lúc bấm mới gọi thì người dùng phải ngồi nhìn.
//

import SwiftUI

struct CccdScanView: View {
    let onBack: () -> Void
    let onStartEkyc: () -> Void

    @StateObject private var sessionManager = EkycSessionManager.shared

    private var isPreparing: Bool {
        sessionManager.state == .loading || sessionManager.state == .idle
    }

    private var isSessionError: Bool {
        if case .error = sessionManager.state { return true }
        return false
    }

    private var ctaLabel: String {
        if isSessionError { return "Thử lại kết nối" }
        if isPreparing { return "Đang chuẩn bị phiên..." }
        return "Bắt đầu xác thực"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            sheet
        }
        .background(Color.white)
        .task { await sessionManager.prepare() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppColor.payInk)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quay lại")

                Spacer()

                Text("Bước 2 / 3")
                    .font(AppFont.beVietnamPro(12))
                    .foregroundStyle(AppColor.payMuted)
            }
            .padding(.bottom, 24)

            StepBar(
                step: 2,
                activeColor: AppColor.brand,
                inactiveColor: AppColor.payMuted.opacity(0.35),
                checkTint: .white
            )

            Text("Xác thực định danh")
                .font(AppFont.beVietnamPro(28, .bold))
                .foregroundStyle(AppColor.payInk)
                .padding(.top, 24)

            Text("Chụp CCCD gắn chip, quét NFC và xác thực khuôn mặt để mở ví")
                .font(AppFont.beVietnamPro(13))
                .foregroundStyle(AppColor.payMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    // MARK: - Thân màn

    private var sheet: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    stepRow(
                        icon: "ic_id_card_outline",
                        title: "Chụp CCCD gắn chip",
                        desc: "Chụp rõ mặt trước và mặt sau, đủ sáng, không bị chói"
                    )
                    stepRow(
                        icon: "ic_nfc_scan",
                        title: "Quét chip NFC",
                        desc: "Áp mặt sau CCCD vào mặt lưng điện thoại và giữ yên"
                    )
                    stepRow(
                        icon: "ic_face_scan",
                        title: "Xác thực khuôn mặt",
                        desc: "Nhìn thẳng vào camera và làm theo hướng dẫn trên màn hình"
                    )

                    privacyNote
                        .padding(.top, 8)
                }
            }

            Button(action: handleCta) {
                HStack(spacing: 8) {
                    Text(ctaLabel)
                        .font(AppFont.beVietnamPro(16, .semibold))
                    if !isPreparing {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(AppColor.brand.opacity(isPreparing ? 0.55 : 1), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isPreparing)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .padding(.top, 28)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .clipShape(.rect(topLeadingRadius: 28, topTrailingRadius: 28))
    }

    /// Đang lỗi phiên thì phải LẤY LẠI phiên trước, chỉ mở SDK khi đã sẵn. Bấm "Thử lại
    /// kết nối" mà mở thẳng SDK với phiên rỗng/hết hạn thì không có tác dụng gì.
    private func handleCta() {
        guard !isPreparing else { return }
        if isSessionError {
            Task {
                guard await sessionManager.prepare(forceRefresh: true) else { return }
                onStartEkyc()
            }
        } else {
            onStartEkyc()
        }
    }

    private func stepRow(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 14) {
            Image(icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.beVietnamPro(15, .semibold))
                    .foregroundStyle(AppColor.payInk)
                Text(desc)
                    .font(AppFont.beVietnamPro(12))
                    .foregroundStyle(AppColor.payMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var privacyNote: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 18))
                .foregroundStyle(AppColor.brand)

            Text("Thông tin của bạn được mã hóa và chỉ dùng cho việc xác thực định danh theo quy định.")
                .font(AppFont.beVietnamPro(12))
                .foregroundStyle(AppColor.brand)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.brandSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    CccdScanView(onBack: {}, onStartEkyc: {})
}
