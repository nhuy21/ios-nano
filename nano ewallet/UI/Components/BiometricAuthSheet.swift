//
//  BiometricAuthSheet.swift
//  nano ewallet
//
//  Sheet xác thực giao dịch bằng Face ID / Touch ID — thay cho `PinEntrySheet` khi thiết bị đã
//  bật sinh trắc. Giữ cùng bố cục (số tiền + người nhận ở trên) để hai sheet thay thế nhau mà
//  người dùng không thấy nhảy layout.
//
//  LUÔN có nút "Dùng mật khẩu": Face ID thất bại, đeo khẩu trang, hay chỉ đơn giản là muốn nhập
//  tay — không bao giờ được để người dùng kẹt.
//

import SwiftUI

struct BiometricAuthSheet: View {
    let amountText: String
    let recipientName: String
    /// Cha gọi API verify-transfer-biometric. Trả về khi xong; lỗi thì set `externalError`.
    var onAuthenticate: () async -> Void
    /// Người dùng chọn nhập mật khẩu — cha đóng sheet này và mở `PinEntrySheet`.
    let onUsePassword: () -> Void
    let onCancel: () -> Void
    @Binding var externalError: String?

    @State private var isAuthenticating = false
    /// Đã tự chạy Face ID lần đầu chưa — `.task` có thể chạy lại khi view bị dựng lại.
    @State private var hasTriedOnce = false

    private let label = BiometricKeyStore.biometryLabel

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(AppColor.line)
                .frame(width: 40, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 16)

            Text("Xác nhận chuyển tiền")
                .font(AppFont.beVietnamPro(17, .bold))
                .foregroundStyle(AppColor.payInk)

            VStack(spacing: 4) {
                Text(amountText)
                    .font(AppFont.beVietnamPro(28, .bold))
                    .foregroundStyle(AppColor.brand)
                Text("Đến \(recipientName)")
                    .font(AppFont.beVietnamPro(13))
                    .foregroundStyle(AppColor.payMuted)
            }
            .padding(.top, 8)
            .padding(.bottom, 24)

            biometryIcon

            Text(statusText)
                .font(AppFont.beVietnamPro(13.5, .medium))
                .foregroundStyle(externalError != nil ? AppColor.error : AppColor.payMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 16)
                .frame(minHeight: 40)

            Spacer(minLength: 16)

            VStack(spacing: 12) {
                // Chỉ hiện "Thử lại" khi đã thất bại — lúc đang quét thì nút này vô nghĩa.
                if externalError != nil, !isAuthenticating {
                    Button("Thử lại \(label)") {
                        Task { await authenticate() }
                    }
                    .buttonStyle(.plain)
                    .font(AppFont.beVietnamPro(15, .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(AppColor.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Button("Dùng mật khẩu") { onUsePassword() }
                    .buttonStyle(.plain)
                    .font(AppFont.beVietnamPro(15, .semibold))
                    .foregroundStyle(AppColor.brand)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(AppColor.brandSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .disabled(isAuthenticating)

                Button("Huỷ") { onCancel() }
                    .buttonStyle(.plain)
                    .font(AppFont.beVietnamPro(14, .semibold))
                    .foregroundStyle(AppColor.payMuted)
                    .disabled(isAuthenticating)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .padding(.top, 4)
        .presentationDetents([.height(460)])
        // Sheet không set nền sẽ lấy nền hệ thống — ở dark mode là ĐEN, mà chữ trong đây
        // đều là màu tối cố định (`payInk`/`payMuted`) nên bị dìm gần như không đọc được.
        // Ghim nền sáng cho khớp Android (bên đó nền sheet là `Color.White` cứng).
        //
        // Phải giãn hết khung TRƯỚC khi tô nền: `VStack` chỉ cao bằng nội dung, mà detent
        // cố định thường cao hơn — tô nền theo `VStack` sẽ để hở dải dưới lộ lại nền đen.
        // `alignment: .top` giữ nội dung ở trên, không bị dồn ra giữa khi giãn.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .presentationDragIndicator(.hidden)
        // Không cho kéo xuống đóng lúc đang chờ BE — giao dịch có thể đã thực thi.
        .interactiveDismissDisabled(isAuthenticating)
        .task {
            // Tự bật Face ID ngay khi sheet hiện: bắt người dùng bấm thêm một nút để mới quét
            // mặt là thêm ma sát vô nghĩa.
            guard !hasTriedOnce else { return }
            hasTriedOnce = true
            await authenticate()
        }
    }

    private var biometryIcon: some View {
        ZStack {
            Circle()
                .fill(AppColor.brandSoft)
                .frame(width: 88, height: 88)
            if isAuthenticating {
                ProgressView()
                    .tint(AppColor.brand)
                    .scaleEffect(1.3)
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 42))
                    .foregroundStyle(externalError != nil ? AppColor.error : AppColor.brand)
            }
        }
    }

    private var iconName: String {
        switch label {
        case "Touch ID": return "touchid"
        case "Face ID": return "faceid"
        default: return "lock.shield"
        }
    }

    private var statusText: String {
        if let externalError { return externalError }
        if isAuthenticating { return "Đang xác thực giao dịch..." }
        return "Xác thực bằng \(label) để hoàn tất chuyển tiền"
    }

    private func authenticate() async {
        guard !isAuthenticating else { return }
        externalError = nil
        isAuthenticating = true
        await onAuthenticate()
        isAuthenticating = false
    }
}
