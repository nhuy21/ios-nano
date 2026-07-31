//
//  DevicesView.swift
//  nano ewallet
//
//  Mirror DevicesScreen.kt — list thiết bị đăng nhập, xoá kèm dialog xác nhận.
//

import SwiftUI

struct DevicesView: View {
    let onBack: () -> Void

    @StateObject private var vm = DevicesViewModel()
    @State private var confirmRemove: DeviceSession?

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(title: "Thiết bị đã đăng nhập", onBack: onBack)

            content
        }
        .background(Color(hex: 0xF7F8FA))
        .task { await vm.load() }
        .alert("Xoá thiết bị", isPresented: Binding(
            get: { confirmRemove != nil },
            set: { if !$0 { confirmRemove = nil } }
        )) {
            Button("Huỷ", role: .cancel) {}
            Button("Xoá", role: .destructive) {
                if let device = confirmRemove {
                    Task { await vm.remove(device.deviceId) }
                }
                confirmRemove = nil
            }
        } message: {
            Text("Bạn có chắc chắn muốn xoá thiết bị này không? Thiết bị sẽ bị đăng xuất khỏi tài khoản.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView()
                .tint(AppColor.brand)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.loadError {
            Text(error)
                .font(.system(size: 14))
                .foregroundStyle(AppColor.payMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.devices.isEmpty {
            Text("Chưa có thiết bị nào")
                .font(.system(size: 14))
                .foregroundStyle(AppColor.payMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    if let removeError = vm.removeError {
                        FieldError(message: removeError)
                    }
                    ForEach(vm.devices) { device in
                        deviceCard(device)
                    }
                }
                .padding(20)
            }
        }
    }

    private func deviceCard(_ device: DeviceSession) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: 0xE3F1FF))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "iphone")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(hex: 0x2C93E8))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(device.deviceName?.isEmpty == false ? device.deviceName! : "Thiết bị không xác định")
                    .font(AppFont.beVietnamPro(15, .semibold))
                    .foregroundStyle(AppColor.payInk)
                Text("Đăng nhập lần cuối: \(formattedLastUsed(device.lastUsedAt))")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.payMuted)
            }

            Spacer()

            if vm.removingDeviceId == device.deviceId {
                ProgressView().tint(AppColor.error)
            } else if device.status == "active" {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                    Text("Thiết bị này")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(AppColor.ok)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppColor.okSoft)
                .clipShape(Capsule())
            } else {
                Button {
                    confirmRemove = device
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColor.error)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Xoá thiết bị")
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppColor.line, lineWidth: 1)
        }
    }

    private func formattedLastUsed(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter.withFractionalSeconds.date(from: iso)
            ?? ISO8601DateFormatter.standard.date(from: iso) else {
            return iso
        }
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let time = timeFormatter.string(from: date)

        if Calendar.current.isDateInToday(date) {
            return "Hôm nay lúc \(time)"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Hôm qua lúc \(time)"
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd-MM-yyyy"
        return "\(dateFormatter.string(from: date)) lúc \(time)"
    }
}

#Preview {
    DevicesView(onBack: {})
}
