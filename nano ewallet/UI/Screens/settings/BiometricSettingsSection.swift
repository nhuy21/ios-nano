//
//  BiometricSettingsSection.swift
//  nano ewallet
//
//  Hai toggle bật/tắt sinh trắc trong màn Bảo mật:
//   - Đăng nhập: Face ID mở Keychain lấy token do BE cấp (KHÔNG lưu mật khẩu trên máy).
//   - Xác thực giao dịch: Face ID mở khoá ký trong Secure Enclave.
//
//  Hai cơ chế độc lập nên tách hai toggle: người dùng có thể muốn tiện khi đăng nhập nhưng vẫn
//  nhập mật khẩu mỗi lần chuyển tiền.
//
//  Toggle LUÔN bấm được (kể cả khi máy chưa thiết lập Face ID) — bấm mới báo lý do, theo đúng
//  yêu cầu thiết kế. Không disable sẵn vì người dùng sẽ không hiểu tại sao mờ.
//

import SwiftUI

struct BiometricSettingsSection: View {

    // Đọc thẳng từ 2 store `nonisolated` chứ không qua `BiometricService` (MainActor-isolated):
    // property initializer của struct không gọi được sang actor khác.
    @State private var loginEnabled = BiometricTokenStore.exists()
    @State private var transferEnabled = BiometricKeyStore.hasKey()

    /// Đang bật cái nào — quyết định sheet mật khẩu áp cho mục nào.
    @State private var pendingEnable: Kind?
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    private let label = BiometricKeyStore.biometryLabel

    private enum Kind: Identifiable {
        case login, transfer
        var id: Int { self == .login ? 0 : 1 }

        var title: String {
            switch self {
            case .login: return "đăng nhập"
            case .transfer: return "xác thực giao dịch"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(AppFont.beVietnamPro(13, .semibold))
                .foregroundStyle(AppColor.payMuted)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                toggleRow(
                    title: "Đăng nhập bằng \(label)",
                    subtitle: "Không cần nhập mật khẩu khi mở app",
                    systemImage: "person.badge.key.fill",
                    isOn: loginEnabled,
                    kind: .login
                )
                Rectangle().fill(AppColor.line).frame(height: 1).padding(.leading, 56)
                toggleRow(
                    title: "Xác thực giao dịch bằng \(label)",
                    subtitle: "Thay cho mật khẩu 6 số khi chuyển tiền",
                    systemImage: "faceid",
                    isOn: transferEnabled,
                    kind: .transfer
                )
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color(hex: 0x784628).opacity(0x14 / 255.0), radius: 6, x: 0, y: 2)

            if let infoMessage {
                Text(infoMessage)
                    .font(AppFont.beVietnamPro(12))
                    .foregroundStyle(AppColor.payMuted)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
            }
        }
        .sheet(item: $pendingEnable) { kind in
            passwordSheet(for: kind)
        }
        .alert("Không thể bật \(label)", isPresented: errorBinding) {
            Button("Đóng", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            // Đồng bộ lại với BE: khoá có trên máy mà BE đã thu hồi (đổi mật khẩu ở máy khác,
            // bị force-logout) thì toggle phải về tắt, không thì người dùng tưởng còn bật rồi
            // tới lúc chuyển tiền mới lỗi.
            await syncTransferStatus()
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    // MARK: - Rows

    private func toggleRow(
        title: String,
        subtitle: String,
        systemImage: String,
        isOn: Bool,
        kind: Kind
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16))
                .foregroundStyle(AppColor.payInk)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.beVietnamPro(15))
                    .foregroundStyle(AppColor.payInk)
                Text(subtitle)
                    .font(AppFont.beVietnamPro(12))
                    .foregroundStyle(AppColor.payMuted)
            }

            Spacer(minLength: 8)

            // Toggle tự vẽ qua Button: `Toggle` của SwiftUI đổi state NGAY khi chạm, mà ở đây
            // bật/tắt phải qua mật khẩu + API nên phải chặn rồi tự set lại sau khi xong.
            Button {
                handleTap(kind: kind, currentlyOn: isOn)
            } label: {
                Capsule()
                    .fill(isOn ? AppColor.brand : AppColor.line)
                    .frame(width: 44, height: 26)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .frame(width: 20, height: 20)
                            .padding(.horizontal, 3)
                            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    }
                    .animation(.easeInOut(duration: 0.18), value: isOn)
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    // MARK: - Sheet mật khẩu

    private func passwordSheet(for kind: Kind) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(AppColor.line)
                .frame(width: 40, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 20)

            Text("Bật \(label) để \(kind.title)")
                .font(AppFont.beVietnamPro(17, .bold))
                .foregroundStyle(AppColor.payInk)

            Text("Nhập mật khẩu 6 số để xác nhận bạn là chủ tài khoản")
                .font(AppFont.beVietnamPro(13))
                .foregroundStyle(AppColor.payMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 8)
                .padding(.bottom, 20)

            PinDotsField(
                value: $password,
                placeholder: "Mật khẩu",
                hasError: false,
                dotsAlignment: .center,
                submitLabel: .done,
                onSubmit: { Task { await enable(kind) } }
            )
            .padding(.horizontal, 24)
            .onChangeNewCompat(of: password) { value in
                if value.count == 6 { Task { await enable(kind) } }
            }

            Spacer(minLength: 20)

            Button("Huỷ") {
                password = ""
                pendingEnable = nil
            }
            .buttonStyle(.plain)
            .font(AppFont.beVietnamPro(14, .semibold))
            .foregroundStyle(AppColor.payMuted)
            .padding(.bottom, 16)
        }
        .padding(.top, 4)
        .disabled(isWorking)
        .overlay { if isWorking { ProgressView().tint(AppColor.brand) } }
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Hành động

    private func handleTap(kind: Kind, currentlyOn: Bool) {
        if currentlyOn {
            Task { await disable(kind) }
            return
        }
        // Máy chưa thiết lập Face ID / không có phần cứng -> báo lý do, không mở sheet mật khẩu.
        if let reason = BiometricKeyStore.unavailableReason() {
            errorMessage = reason
            return
        }
        password = ""
        pendingEnable = kind
    }

    private func enable(_ kind: Kind) async {
        guard password.count == 6, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            switch kind {
            case .login:
                try await BiometricService.enableForLogin(password: password)
                loginEnabled = true
                infoMessage = nil
            case .transfer:
                let result = try await BiometricService.enableForTransfer(password: password)
                transferEnabled = true
                // Cooling-off: BE chặn xác thực bằng sinh trắc trong 24h đầu. Nói trước để người
                // dùng không tưởng tính năng lỗi khi lần chuyển tiền đầu vẫn đòi mật khẩu.
                infoMessage = Self.coolingOffNote(until: result.coolingOffUntil, label: label)
            }
            password = ""
            pendingEnable = nil
        } catch let error as APIError {
            errorMessage = error.message
            password = ""
        } catch let error as BiometricKeyError {
            errorMessage = error.localizedDescription
            password = ""
        } catch {
            errorMessage = "Không bật được \(label), vui lòng thử lại"
            password = ""
        }
    }

    private func disable(_ kind: Kind) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            switch kind {
            case .login:
                try await BiometricService.disableForLogin()
                loginEnabled = false
            case .transfer:
                try await BiometricService.disableForTransfer()
                transferEnabled = false
                infoMessage = nil
            }
        } catch {
            // Khoá/token trên MÁY đã bị xoá trước khi gọi API (xem BiometricService), nên dù API
            // lỗi thì tính năng cũng đã tắt thật ở đây. Cập nhật UI theo trạng thái máy.
            switch kind {
            case .login: loginEnabled = BiometricTokenStore.exists()
            case .transfer: transferEnabled = BiometricKeyStore.hasKey()
            }
        }
    }

    /// Đọc trạng thái từ BE và chỉnh lại toggle giao dịch cho khớp.
    private func syncTransferStatus() async {
        guard let status = try? await BiometricService.transferStatus() else { return }
        let hasLocalKey = BiometricKeyStore.hasKey()

        // BE đã thu hồi (đổi mật khẩu, force-logout) mà máy còn khoá -> xoá khoá mồ côi.
        if !status.enabled, hasLocalKey {
            BiometricKeyStore.deleteKey()
            transferEnabled = false
            return
        }
        transferEnabled = status.enabled && hasLocalKey
        if status.inCoolingOff, let until = status.coolingOffUntil {
            infoMessage = Self.coolingOffNote(until: until, label: label)
        }
    }

    private static func coolingOffNote(until iso: String, label: String) -> String {
        let base = "Vì mới bật, giao dịch trong 24 giờ đầu vẫn cần nhập mật khẩu."
        guard let date = ISO8601DateFormatter.withFractionalSeconds.date(from: iso)
            ?? ISO8601DateFormatter.standard.date(from: iso) else { return base }
        let formatter = DateFormatter.app("HH:mm dd/MM")
        return "\(base) \(label) dùng được cho mọi giao dịch từ \(formatter.string(from: date))."
    }
}
