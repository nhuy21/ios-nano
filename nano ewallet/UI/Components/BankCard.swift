//
//  BankCard.swift
//  nano ewallet
//
//  Mirror BankCard.kt — mặt trước thẻ ngân hàng liên kết: nền gradient theo MÀU
//  THƯƠNG HIỆU của ngân hàng, logo thật tint 1 màu + hạ mờ để "chìm" xuống nền
//  (watermark góc phải-dưới). KHÔNG hiển thị số dư (đây là bank, không phải ví).
//  Màu chữ tự đổi trắng/tối theo độ sáng nền để luôn đọc được.
//

import SwiftUI
import Foundation

struct BankCard: View {
    let bankName: String
    let accountNumber: String
    let holderName: String
    let syncedDate: String
    var brandColorHex: String?
    var logoUrl: String?
    /// Mã BIN — để tra logo emblem LOCAL (đẹp hơn logo remote, nhiều logo remote là
    /// wordmark trông xấu khi làm watermark). Mirror `localBankLogoRes()` bên Android.
    var bin: String?

    /// Màu brand mặc định khi ngân hàng chưa có brandColor (mirror FallbackBrand).
    private static let fallbackBrand = Color(hex: 0x177C44)

    private var brandComponents: (red: Double, green: Double, blue: Double) {
        guard let hex = brandColorHex?.trimmingCharacters(in: .whitespacesAndNewlines),
              !hex.isEmpty else {
            return (0x17 / 255, 0x7C / 255, 0x44 / 255)
        }
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            return (0x17 / 255, 0x7C / 255, 0x44 / 255)
        }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }

    private var brand: Color {
        let c = brandComponents
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
    }

    /// Trộn màu về phía đen 22% — dựng cuối gradient tối hơn (mirror `darken(0.22f)`).
    private var brandDarkened: Color {
        let c = brandComponents
        let f = 0.22
        return Color(.sRGB, red: c.red * (1 - f), green: c.green * (1 - f), blue: c.blue * (1 - f), opacity: 1)
    }

    /// Độ sáng cảm nhận (mirror `Color.luminance()` của Compose, hệ số sRGB tuyến tính).
    private var isOnLightBackground: Bool {
        let c = brandComponents
        func linear(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
        return luminance > 0.6
    }

    private var ink: Color {
        isOnLightBackground ? Color(hex: 0x111827) : .white
    }

    /// Nền tối tint trắng cho logo sáng lên, nền sáng tint đen cho tối đi.
    private var watermarkTint: Color {
        isOnLightBackground ? .black : .white
    }

    var body: some View {
        GeometryReader { geo in
            let cardWidth = geo.size.width
            let cardHeight = cardWidth * 0.585

            ZStack(alignment: .bottomTrailing) {
                LinearGradient(
                    colors: [brand, brandDarkened],
                    startPoint: .top, endPoint: .bottom
                )

                watermark(cardHeight: cardHeight)

                content
                    .padding(20)
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
        }
        .aspectRatio(1 / 0.585, contentMode: .fit)
    }

    /// Logo cỡ lớn lệch góc phải-dưới, mờ, bị bo góc thẻ cắt bớt (nằm sau nội dung).
    /// Ưu tiên emblem LOCAL port từ vector Android; chưa có thì rơi về `logoUrl` remote.
    @ViewBuilder
    private func watermark(cardHeight: CGFloat) -> some View {
        let size = cardHeight * 1.15
        Group {
            if let shape = BankLogoPaths.shape(bin: bin) {
                ZStack {
                    ForEach(Array(shape.paths.enumerated()), id: \.offset) { _, pathData in
                        SVGPath(pathData: pathData, viewBox: shape.viewBox)
                            .fill(watermarkTint, style: FillStyle(eoFill: shape.usesEvenOdd))
                    }
                }
            } else if let logoUrl, let url = URL(string: logoUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(watermarkTint)
                } placeholder: {
                    Color.clear
                }
            }
        }
        .frame(width: size, height: size)
        .opacity(isOnLightBackground ? 0.13 : 0.16)
        .offset(x: cardHeight * 0.20, y: cardHeight * 0.22)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Ba Spacer chia đều chỗ trống dư: khối tên ngân hàng tụt xuống, khối số
            // tài khoản nhích lên, thay vì cả hai bị ép sát hai mép thẻ.
            Spacer(minLength: 0)

            Text(bankName)
                .font(AppFont.beVietnamPro(18, .heavy))
                .foregroundStyle(ink)
                .tracking(0.3)
                .lineLimit(1)

            Spacer().frame(height: 4)

            Text("Ngân hàng liên kết")
                .font(AppFont.beVietnamPro(12))
                .foregroundStyle(ink.opacity(0.75))

            Spacer(minLength: 0)

            Text("Số thẻ / tài khoản")
                .font(AppFont.beVietnamPro(11))
                .foregroundStyle(ink.opacity(0.6))
                .tracking(0.5)

            Spacer().frame(height: 3)

            Text(accountNumber)
                .font(AppFont.beVietnamPro(16, .semibold))
                .foregroundStyle(ink)
                .tracking(2)

            Spacer().frame(height: 12)

            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CHỦ TÀI KHOẢN")
                        .font(AppFont.beVietnamPro(10))
                        .foregroundStyle(ink.opacity(0.55))
                        .tracking(0.8)
                    Text(holderName)
                        .font(AppFont.beVietnamPro(14, .bold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(syncedDate)
                    .font(AppFont.beVietnamPro(11))
                    .foregroundStyle(ink.opacity(0.6))
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview {
    VStack(spacing: 12) {
        BankCard(
            bankName: "Vietcombank",
            accountNumber: "1234 5678 9012",
            holderName: "DANG NGOC KHIEU",
            syncedDate: "Đồng bộ 13/07/2026",
            brandColorHex: "#177c44",
            bin: "970436"
        )
        BankCard(
            bankName: "Agribank",
            accountNumber: "9876 5432 1098",
            holderName: "NGUYEN VAN A",
            syncedDate: "Đồng bộ 01/08/2026",
            brandColorHex: "#F0C41B",
            bin: "970405"
        )
    }
    .padding(16)
    .background(Color.white)
}
