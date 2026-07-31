//
//  DevicesViewModel.swift
//  nano ewallet
//
//  Mirror phần state của DevicesScreen.kt.
//

import Foundation
import Combine

@MainActor
final class DevicesViewModel: ObservableObject {

    @Published private(set) var devices: [DeviceSession] = []
    @Published var isLoading = false
    @Published var loadError: String?
    @Published var removingDeviceId: String?
    @Published var removeError: String?

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            devices = try await AuthService.getDevices()
        } catch {
            loadError = (error as? APIError)?.message ?? "Không tải được danh sách thiết bị"
        }
    }

    func remove(_ deviceId: String) async {
        removingDeviceId = deviceId
        removeError = nil
        defer { removingDeviceId = nil }
        do {
            try await AuthService.removeDevice(deviceId: deviceId)
            devices.removeAll { $0.deviceId == deviceId }
        } catch {
            removeError = (error as? APIError)?.message ?? "Xoá thiết bị thất bại, vui lòng thử lại"
        }
    }
}
