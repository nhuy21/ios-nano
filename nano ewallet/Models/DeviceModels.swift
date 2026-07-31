//
//  DeviceModels.swift
//  nano ewallet
//
//  Mirror be/src/modules/push (DeviceTokenApi.kt bên Android).
//

import Foundation

struct RegisterDeviceRequest: Encodable {
    let token: String
    let deviceId: String
    /// Android gửi "ANDROID" — iOS gửi "IOS".
    let platform: String = "IOS"
}

struct UnregisterDeviceRequest: Encodable {
    let deviceId: String
}
