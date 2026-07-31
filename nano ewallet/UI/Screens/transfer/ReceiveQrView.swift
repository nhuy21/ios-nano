//
//  ReceiveQrView.swift
//  nano ewallet
//
//  Mirror ReceiveQrScreen.kt — "QR của tôi" (nhận tiền). Tự build VietQR (EMVCo) từ
//  vaBankNo/vaNumber (virtual account Bảo Kim cấp riêng cho ví, KHÁC bkUsername) tại
//  client bằng VietQrBuilder — không dùng ảnh qr_path. Sinh ảnh QR bằng CoreImage
//  (CIFilter.qrCodeGenerator) thay ZXing bên Android.
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

@MainActor
struct ReceiveQrView: View {
    let onBack: () -> Void

    @StateObject private var wallet = WalletStore.shared

    @State private var fixedAmount: Int?
    @State private var showAmountSheet = false
    @State private var amountInput = ""
    @State private var shareItem: ShareableImage?
    @State private var toastMessage: String?

    private var qrContent: String? {
        guard let bin = wallet.vaBankNo, !bin.isEmpty,
              let number = wallet.vaNumber, !number.isEmpty else { return nil }
        return VietQrBuilder.build(
            bankBin: bin, accountNumber: number,
            purposeMessage: "Nap so du vi Baokim", amount: fixedAmount
        )
    }

    private var displayName: String { wallet.accName ?? "Ví Nano" }
    private var displayNo: String { wallet.bkUsername ?? "—" }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 16) {
                    billCard
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }
            actionRow
        }
        .background(
            LinearGradient(
                colors: [Color(hex: 0x17A06B), Color(hex: 0x00754A)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .task { await wallet.refresh() }
        .sheet(isPresented: $showAmountSheet) {
            amountSheet
        }
        .sheet(item: $shareItem) { item in
            ActivityShareSheet(items: [item.image])
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
                    .font(AppFont.beVietnamPro(13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .padding(.bottom, 100)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Text("QR nhận tiền")
                .font(AppFont.beVietnamPro(20, .bold))
                .foregroundStyle(.white)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Bill card

    private var billCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(displayName)
                    .font(AppFont.beVietnamPro(17, .bold))
                    .foregroundStyle(AppColor.payInk)
                Text("Số ví · \(displayNo)")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColor.payMuted)
            }
            .padding(.top, 20)

            if let qrContent, let image = Self.qrImage(for: qrContent) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(width: 220, height: 220)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColor.bgSoft)
                    .frame(width: 220, height: 220)
                    .overlay {
                        Text("Chưa có số ví để tạo mã")
                            .font(.system(size: 13))
                            .foregroundStyle(AppColor.payMuted)
                            .multilineTextAlignment(.center)
                            .padding(24)
                    }
            }

            if let fixedAmount {
                Text(fixedAmount.vndFormatted)
                    .font(AppFont.baloo2(22, .bold))
                    .foregroundStyle(AppColor.brand)
            }

            Button {
                amountInput = fixedAmount.map { String($0) } ?? ""
                showAmountSheet = true
            } label: {
                Text(fixedAmount != nil ? "+ Đổi số tiền" : "+ Thêm số tiền")
                    .font(AppFont.beVietnamPro(15, .semibold))
                    .foregroundStyle(AppColor.brand)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 12, y: 6)
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: 0) {
            actionButton(icon: "square.and.arrow.up", title: "Chia sẻ mã QR") {
                shareQr()
            }
            actionButton(icon: "square.and.arrow.down", title: "Lưu vào thư viện") {
                saveQr()
            }
        }
        .padding(.vertical, 14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private func actionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(AppColor.brand)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColor.payInk)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Amount sheet

    private var amountSheet: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(AppColor.line)
                .frame(width: 40, height: 4)
                .padding(.top, 8)

            Text("Thêm số tiền vào mã QR")
                .font(AppFont.beVietnamPro(16, .bold))
                .foregroundStyle(AppColor.payInk)

            AppTextField(
                text: amountFieldBinding, placeholder: "0",
                keyboardType: .numberPad, submitLabel: .done, digitsOnly: true
            )
            .padding(.horizontal, 20)

            HStack(spacing: 12) {
                Button("Bỏ số tiền") {
                    fixedAmount = nil
                    showAmountSheet = false
                }
                .buttonStyle(.plain)
                .font(AppFont.beVietnamPro(14, .semibold))
                .foregroundStyle(AppColor.payMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)

                Button("Xong") {
                    fixedAmount = Int(amountInput)
                    showAmountSheet = false
                }
                .buttonStyle(.plain)
                .font(AppFont.beVietnamPro(14, .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppColor.brand)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .presentationDetents([.height(240)])
        .presentationDragIndicator(.hidden)
    }

    private var amountFieldBinding: Binding<String> {
        Binding(
            get: { amountInput },
            set: { amountInput = String($0.filter(\.isNumber).prefix(9)) }
        )
    }

    // MARK: - Share / Save

    private func shareQr() {
        guard let qrContent, let image = Self.qrImage(for: qrContent) else {
            toastMessage = "Chưa có số ví để tạo mã"
            hideToastLater()
            return
        }
        shareItem = ShareableImage(image: image)
    }

    private func saveQr() {
        guard let qrContent, let image = Self.qrImage(for: qrContent) else {
            toastMessage = "Chưa có số ví để tạo mã"
            hideToastLater()
            return
        }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        toastMessage = "Đã lưu mã QR vào thư viện"
        hideToastLater()
    }

    private func hideToastLater() {
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            toastMessage = nil
        }
    }

    /// Sinh ảnh QR từ chuỗi EMVCo qua CoreImage — mirror ZXing `QRCodeWriter` bên Android
    /// (error correction cao nhất để giữ độ tin cậy khi hiển thị nhỏ).
    private static func qrImage(for content: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = "H"
        guard let outputImage = filter.outputImage else { return nil }
        let scale = 640 / outputImage.extent.width
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private struct ShareableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ReceiveQrView(onBack: {})
}
