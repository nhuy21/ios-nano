//
//  VietQrBuilder.swift
//  nano ewallet
//
//  Tự build chuỗi VietQR (EMVCo TLV, chuẩn NAPAS) tại client — mirror
//  `buildVietQrContent()`/`emvTlv()`/`crc16Ccitt()` trong ReceiveQrScreen.kt. Dùng cho
//  màn "QR của tôi" (nhận tiền), KHÁC luồng quét (luồng quét gửi rawValue lên BE
//  `banks/parse-qr` để verify CRC + tra tên chủ TK, không tự parse ở client).
//

import Foundation

enum VietQrBuilder {
    /// Build chuỗi EMVCo hoàn chỉnh (kèm CRC) cho 1 tài khoản VietQR NAPAS — mirror
    /// `buildVietQrContent()` (ReceiveQrScreen.kt:501-521) từng byte một.
    /// - Parameters:
    ///   - bankBin: mã BIN ngân hàng (vd vaBankNo — virtual account Bảo Kim cấp).
    ///   - accountNumber: số tài khoản/VA (vd vaNumber).
    ///   - purposeMessage: nội dung gợi ý (tag 62/08) — nil nếu không gắn sẵn.
    ///   - amount: số tiền cố định gắn vào QR (tag 54) — nil nếu để người chuyển tự nhập.
    static func build(bankBin: String, accountNumber: String, purposeMessage: String? = nil, amount: Int? = nil) -> String {
        let merchantAccountInfo = tlv("00", "A000000727")
            + tlv("01", tlv("00", bankBin) + tlv("01", accountNumber))
            + tlv("02", "QRIBFTTA")

        var payload = ""
        payload += tlv("00", "01") // Payload Format Indicator
        payload += tlv("01", amount != nil ? "12" : "11") // Point of Initiation Method
        payload += tlv("38", merchantAccountInfo) // Merchant Account Information (VietQR/NAPAS)
        payload += tlv("53", "704") // Transaction Currency: VND
        if let amount, amount > 0 {
            payload += tlv("54", String(amount)) // Transaction Amount
        }
        payload += tlv("58", "VN") // Country Code
        if let purposeMessage, !purposeMessage.trimmingCharacters(in: .whitespaces).isEmpty {
            payload += tlv("62", tlv("08", purposeMessage)) // Additional Data Field (purpose)
        }
        payload += "6304" // CRC tag + length, giá trị tính sau
        return payload + crc16CCITT(payload)
    }

    private static func tlv(_ tag: String, _ value: String) -> String {
        let length = String(format: "%02d", value.utf8.count)
        return "\(tag)\(length)\(value)"
    }

    /// CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF) — chuẩn EMVCo tag "63".
    private static func crc16CCITT(_ input: String) -> String {
        var crc: UInt16 = 0xFFFF
        for byte in input.utf8 {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc <<= 1
                }
            }
        }
        return String(format: "%04X", crc)
    }
}
