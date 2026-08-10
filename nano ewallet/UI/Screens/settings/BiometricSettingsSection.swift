//
//  BiometricSettingsSection.swift
//  nano ewallet
//
//  Hai toggle bật/tắt sinh trắc, xếp trong khối "Cài đặt" của màn Cá nhân:
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

    /// HAI HÀNG TRẦN, không tự bọc thẻ/tiêu đề: section này nằm trong khối "Cài đặt" của
    /// màn Cá nhân, nền trắng + bo góc + shadow do `menuSection` bên đó lo. Tự bọc thêm một
    /// lớp nữa sẽ thành thẻ lồng trong thẻ.
    var body: some View {
        VStack(spacing: 0) {
            // Tiêu đề NGẮN, không kèm "bằng Face ID": bỏ dòng mô tả rồi nên chỉ còn một
            // dòng, mà "Xác thực giao dịch bằng Face ID" dài quá khung còn lại sau icon và
            // công tắc — nó bị cắt thành "Xác thực giao dịch bằng F...". Icon `faceid` đứng
            // ngay cạnh đã nói rõ đây là Face ID.
            toggleRow(
                title: "Đăng nhập bằng \(label)",
                systemImage: "person.badge.key.fill",
                isOn: loginEnabled,
                kind: .login
            )
            Rectangle().fill(AppColor.line).frame(height: 1).padding(.leading, 56)
            toggleRow(
                title: "Xác thực giao dịch",
                systemImage: "faceid",
                isOn: transferEnabled,
                kind: .transfer
            )

            if let infoMessage {
                Text(infoMessage)
                    .font(AppFont.beVietnamPro(12))
                    .foregroundStyle(AppColor.payMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
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
        systemImage: String,
        isOn: Bool,
        kind: Kind
    ) -> some View {
        HStack(spacing: 12) {
            // Icon 24pt như hàng "Loa báo nhận tiền" (`toggleRowIcon` bên SettingsView),
            // không phải 16pt của hàng có chevron — cùng loại hàng thì cùng cỡ icon.
            Image(systemName: systemImage)
                .font(.system(size: 24))
                .foregroundStyle(AppColor.payInk)
                .frame(width: 28)

            // Cùng cỡ chữ với mọi hàng khác trong màn Cá nhân.
            //
            // `lineLimit(1)` + `minimumScaleFactor`: nếu khung vẫn hẹp (máy nhỏ, người dùng
            // tăng cỡ chữ hệ thống, hoặc `label` là "Touch ID" dài hơn) thì chữ co lại chút
            // chứ KHÔNG bị cắt đuôi thành "...".
            Text(title)
                .font(AppFont.beVietnamPro(SettingsRowMetrics.titleFontSize))
                .foregroundStyle(AppColor.payInk)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 8)

            // `Toggle` HỆ THỐNG cho giống hàng "Loa báo nhận tiền" (trước đây là capsule tự
            // vẽ nên hai khối nhìn lệch nhau).
            //
            // Bind qua `Binding` tự dựng chứ không bind thẳng vào `@State`: bật/tắt ở đây
            // phải qua sheet mật khẩu + API, nên `get` LUÔN trả trạng thái thật còn `set`
            // chỉ khởi động luồng xử lý. Toggle sẽ tự nhảy về đúng chỗ vì `get` không đổi —
            // chỉ đổi sau khi `enable`/`disable` chạy xong.
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { _ in handleTap(kind: kind, currentlyOn: isOn) }
            ))
            .labelsHidden()
            .tint(AppColor.brand)
        }
        .padding(.horizontal, 16)
        // Cùng chiều cao với mọi hàng khác trong màn Cá nhân.
        .frame(height: SettingsRowMetrics.height)
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
            .buttonStyle(PressableButtonStyle())
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
        // Chặn ngay tại đây thay vì `disabled(isWorking)` trên `Toggle`: `Toggle` hệ thống
        // khi bị disable sẽ MỜ đi, nhìn như tính năng không dùng được. `enable`/`disable`
        // cũng tự guard `isWorking` nên đây là lớp chặn thứ hai, không phải duy nhất.
        guard !isWorking else { return }
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
